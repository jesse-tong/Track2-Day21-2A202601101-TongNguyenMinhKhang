# Báo Cáo Thực Hành Lab Day 21

**Học viên:** Tống Nguyễn Minh Khang   
**Tập dữ liệu:** Wine Quality Dataset (UCI Machine Learning Repository)  

## 1. Lựa Chọn Bộ Siêu Tham Số & Phân Tích Thực Nghiệm (Bước 1)

Dựa trên quá trình tracking thí nghiệm bằng MLflow UI, nhiều bộ siêu tham số và mô hình đã được thử nghiệm và so sánh. Mô hình RandomForestClassifier được lựa chọn làm mô hình chính nhờ khả năng khái quát hóa vượt trội trên dữ liệu dạng bảng (tabular data) có độ nhiễu cao.

### Bộ siêu tham số tối ưu đã chọn (`params.yaml`):
```yaml
n_estimators: 300
max_depth: 20
min_samples_split: 3
max_features: 0.38
```

### Lý do lựa chọn:
1. `n_estimators: 300`: Đảm bảo đủ số lượng cây để trung bình hóa xác suất dự đoán, giúp giảm phương sai (variance) mà không làm tăng đáng kể chi phí tính toán trong pipeline CI/CD.
2. `max_depth: 20`: Khống chế độ sâu hợp lý để cây học được các đặc trưng (nồng độ cồn, axit bay hơi, SO2, tỷ trọng) mà không bị overfitting.
3. `min_samples_split: 3`: Đòi hỏi ít nhất 3 mẫu để thực hiện phân nhánh tại mỗi node nội bộ, giúp các nút lá có tính tổng quát tốt hơn so với giá trị mặc định (`2`).
4. `max_features: 0.38` (~38% tổng số đặc trưng được chọn ngẫu nhiên tại mỗi điểm rẽ nhánh): Tăng tính đa dạng giữa các cây (de-correlating trees), mang lại độ chính xác cao nhất trên tập đánh giá (`eval.csv`) đạt 0.686 (so với 0.650 của LightGBM, 0.620 của SVC và 0.602 của AdaBoost).

## 2. So Sánh Hiệu Suất Giữa Bước 2 và Bước 3

| Chỉ số đánh giá | Bước 2 (Phase 1: 2,998 mẫu) | Bước 3 (Phase 1 + 2: 5,996 mẫu) |
| :--- | :---: | :---: | :---: |
| **Accuracy** | **0.686** | **0.752** |
| **F1-Score (weighted)** | **0.685** | **0.751** |

### So sánh & Đánh giá:
- Tác động của dữ liệu mới: Khi bổ sung thêm 2,998 mẫu dữ liệu từ `train_phase2.csv` (tăng gấp đôi kích thước tập huấn luyện lên 5,996 mẫu), cả hai chỉ số Accuracy và F1-Score đều tăng trưởng từ 68.6% lên 75.2%.
- Khả năng tự động hóa: Kết quả chứng minh tính hiệu quả của quy trình MLOps trên GitHub Actions: khi dữ liệu mới được đẩy lên DVC và kích hoạt commit, mô hình mới tự động huấn luyện, vượt qua ngưỡng kiểm định chất lượng (`Eval Gate >= 0.70`), và được tự động triển khai cập nhật lên máy chủ inference FastAPI.

## 3. Khó Khăn Gặp Phải & Cách Giải Quyết

Trong quá trình triển khai hệ thống CI/CD và MLOps, một số khó khăn thực tế đã phát sinh và được xử lý:

| Vấn đề gặp phải | Nguyên nhân | Giải pháp xử lý |
| :--- | :--- | :--- |
| 1. Lỗi `Missing cache files` / `403 Forbidden` khi `dvc pull` trên GitHub Actions | Runner GitHub Actions báo lỗi `Missing cache files: md5: c43af...` hoặc `403 Forbidden: failed to connect to s3 (/dvc/files/md5)`. Nguyên nhân do  remote URL bị thiếu bucket (`s3:///dvc`). | Chạy `dvc push` từ máy local để đồng bộ đầy đủ cache lên S3 remote trước khi `git push`, đồng thời bổ sung bước cấu hình `dvc remote modify myremote url "s3://${CLOUD_BUCKET}/dvc"` trong file workflow CI/CD. |


