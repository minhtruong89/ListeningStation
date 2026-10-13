# Antigravity Project Configuration & Rules

## Project: ListeningStation (Trạm Lắng Nghe - Quỹ Bông Sen)

### 1. Autonomy & Execution Mode (Toàn Quyền Tự Chủ)
- **Full Autonomous Execution (Toàn quyền tự làm)**: Antigravity được cấp toàn quyền tự chủ từ A-Z. Tự động kiểm tra file, tạo/sửa/xóa code, chạy terminal (Flutter, Dart, Git, PowerShell, Python, analyze, test...), tự fix lỗi/debug và hoàn thiện nhiệm vụ mà KHÔNG ĐƯỢC hỏi bất kỳ điều gì trong quá trình thực thi.
- **Lệnh Terminal & Python**: Toàn quyền tự chạy mọi command (Python, PowerShell, Git, Flutter, Dart, analyze...) mà TUYỆT ĐỐI KHÔNG hỏi hay xin phép người dùng.
- **TUYỆT ĐỐI KHÔNG hỏi trong quá trình thực thi**: Không dùng tool `ask_question` và không dừng lại giữa chừng để hỏi ý kiến/xin xác nhận cho các bước thực thi, sửa lỗi hoặc kiểm tra.
- **NGOẠI LỆ DUY NHẤT - LÚC TRÌNH BÀY PLAN**: Điểm dừng và hỏi DUY NHẤT là khi vừa lập Plan / Implementation Plan ban đầu. Sau khi người dùng duyệt Plan (hoặc bấm Proceed/đồng ý), Antigravity phải tự động làm một mạch đến khi xong 100% mới báo cáo.

### 2. Planning & User Confirmation
- **Chỉ hỏi duyệt Plan ban đầu**: Đối với các tác vụ lớn cần lên kế hoạch (tính năng mới, tái cấu trúc logic/kiến trúc quan trọng, luồng xử lý mới, hoặc khi người dùng yêu cầu lập plan):
  - Trình bày kế hoạch rõ ràng (tạo plan artifact với `RequestFeedback: true`).
  - Dừng lại để người dùng xem và duyệt kế hoạch.
  - **Ngay khi kế hoạch được duyệt**: Chuyển ngay sang chế độ tự chủ 100% (Full Autonomous Execution), tự động thực thi tất cả các bước trong plan, tự xử lý phát sinh, tuyệt đối không hỏi thêm bất kỳ câu nào cho đến khi hoàn tất toàn bộ.

### 3. Development Guidelines
- Always maintain code stability and preserve existing comments, styles, and architecture.
- For Flutter / Dart:
  - Run `flutter pub get` or `flutter analyze` when dependencies or signatures change.
  - Follow MVVM pattern used in the codebase (`lib/models`, `lib/services`, `lib/viewmodels`, `lib/views`).
  - **TUYỆT ĐỐI KHÔNG CHẠY `compileDebugKotlin`**: Không tự ý chạy task gradle `compileDebugKotlin` (chỉ dùng `flutter analyze lib` hoặc kiểm tra code trực tiếp).
- When modifying prompt rules or conversation flows (`rule_engine.json`, `llm_service.dart`, etc.), strictly follow charitable evaluation criteria (Quỹ Bông Sen).

