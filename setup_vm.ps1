param(
    [switch]$destroy
)

$env:AWS_PROFILE = "day21"
$env:AWS_DEFAULT_REGION = "ap-southeast-1"

$REGION = $env:AWS_DEFAULT_REGION
$PROFILE = $env:AWS_PROFILE

$INSTANCE_NAME = "inference-api"
$SG_NAME = "inference-sg"
$KEY_NAME = "inference-key-2"
$KEY_PATH = Join-Path (Get-Location) "$KEY_NAME.pem"

aws sts get-caller-identity

if ($destroy) {
    Write-Host "Destroying inference infrastructure..."

    # 1. Find instance by Name tag
    $INSTANCE_IDS = aws ec2 describe-instances `
        --filters `
            "Name=tag:Name,Values=$INSTANCE_NAME" `
            "Name=instance-state-name,Values=pending,running,stopping,stopped" `
        --query "Reservations[].Instances[].InstanceId" `
        --output text `
        --profile $PROFILE `
        --region $REGION

    if ($INSTANCE_IDS) {
        Write-Host "Terminating instances: $INSTANCE_IDS"

        aws ec2 terminate-instances `
            --instance-ids $INSTANCE_IDS `
            --profile $PROFILE `
            --region $REGION

        Write-Host "Waiting for instances to terminate..."

        aws ec2 wait instance-terminated `
            --instance-ids $INSTANCE_IDS `
            --profile $PROFILE `
            --region $REGION

        Write-Host "Instances terminated."
    }
    else {
        Write-Host "No inference instances found."
    }

    # 2. Find Security Group
    $SG_ID = aws ec2 describe-security-groups `
        --filters "Name=group-name,Values=$SG_NAME" `
        --query "SecurityGroups[0].GroupId" `
        --output text `
        --profile $PROFILE `
        --region $REGION

    if ($SG_ID -and $SG_ID -ne "None") {
        Write-Host "Deleting Security Group: $SG_ID"

        aws ec2 delete-security-group `
            --group-id $SG_ID `
            --profile $PROFILE `
            --region $REGION

        Write-Host "Security Group deleted."
    }
    else {
        Write-Host "Security Group not found."
    }

    exit 0
}

$VPC_ID = aws ec2 describe-vpcs `
    --filters "Name=is-default,Values=true" `
    --query "Vpcs[0].VpcId" `
    --output text `
    --profile $PROFILE `
    --region $REGION

Write-Host "VPC: $VPC_ID"

$SUBNET_ID = aws ec2 describe-subnets `
    --filters "Name=vpc-id,Values=$VPC_ID" `
    --query "Subnets[0].SubnetId" `
    --output text `
    --profile $PROFILE `
    --region $REGION

Write-Host "Subnet: $SUBNET_ID"

# Get or create Security Group
$SG_ID = aws ec2 describe-security-groups `
    --filters "Name=group-name,Values=$SG_NAME" "Name=vpc-id,Values=$VPC_ID" `
    --query "SecurityGroups[0].GroupId" `
    --output text `
    --profile $PROFILE `
    --region $REGION

if (-not $SG_ID -or $SG_ID -eq "None") {
    Write-Host "Creating Security Group: $SG_NAME"

    $SG_ID = aws ec2 create-security-group `
        --group-name $SG_NAME `
        --description "SSH and inference API" `
        --vpc-id $VPC_ID `
        --query "GroupId" `
        --output text `
        --profile $PROFILE `
        --region $REGION

    if (-not $SG_ID -or $SG_ID -eq "None") {
        throw "Failed to create Security Group."
    }
}
else {
    Write-Host "Using existing Security Group: $SG_ID"
}

Write-Host "Security Group: $SG_ID"

aws ec2 authorize-security-group-ingress `
    --group-id $SG_ID `
    --protocol tcp `
    --port 22 `
    --cidr 0.0.0.0/0 `
    --profile $PROFILE `
    --region $REGION

aws ec2 authorize-security-group-ingress `
    --group-id $SG_ID `
    --protocol tcp `
    --port 8000 `
    --cidr 0.0.0.0/0 `
    --profile $PROFILE `
    --region $REGION

$KEY_PATH = Join-Path (Get-Location) "$KEY_NAME.pem"

aws ec2 create-key-pair `
    --key-name $KEY_NAME `
    --query "KeyMaterial" `
    --output text `
    --profile $PROFILE `
    --region $REGION | Out-File -FilePath $KEY_PATH -Encoding ascii

Write-Host "Key saved to: $KEY_PATH"

icacls $KEY_PATH /inheritance:r
icacls $KEY_PATH /grant:r "$($env:USERNAME):(R)"

$AMI_ID = aws ec2 describe-images `
    --owners 099720109477 `
    --filters `
        "Name=name,Values=ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*" `
        "Name=state,Values=available" `
        "Name=architecture,Values=x86_64" `
        "Name=root-device-type,Values=ebs" `
    --query "Images | sort_by(@, &CreationDate) | [-1].ImageId" `
    --output text `
    --profile $PROFILE `
    --region $REGION

Write-Host "Ubuntu AMI: $AMI_ID"

aws ec2 describe-images `
    --image-ids $AMI_ID `
    --query "Images[0].[ImageId,Name,CreationDate]" `
    --output table `
    --profile $PROFILE `
    --region $REGION

$INSTANCE_ID = aws ec2 run-instances `
    --image-id $AMI_ID `
    --instance-type t3.micro `
    --key-name $KEY_NAME `
    --security-group-ids $SG_ID `
    --subnet-id $SUBNET_ID `
    --associate-public-ip-address `
    --count 1 `
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=inference-api}]" `
    --query "Instances[0].InstanceId" `
    --output text `
    --profile $PROFILE `
    --region $REGION

Write-Host "Instance: $INSTANCE_ID"

aws ec2 wait instance-running `
    --instance-ids $INSTANCE_ID `
    --profile $PROFILE `
    --region $REGION

$PUBLIC_IP = aws ec2 describe-instances `
    --instance-ids $INSTANCE_ID `
    --query "Reservations[0].Instances[0].PublicIpAddress" `
    --output text `
    --profile $PROFILE `
    --region $REGION

Write-Host "Public IP: $PUBLIC_IP"