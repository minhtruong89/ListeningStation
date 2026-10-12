# Antigravity Project Configuration & Rules

## Project: ListeningStation (Trạm Lắng Nghe - Quỹ Bông Sen)

### 1. Autonomy & Execution Mode
- **Full Autonomous Permissions**: Antigravity is granted full permissions to inspect, create, edit, and delete files within the project workspace.
- **Auto-Execution of Routine Tools**: Terminal commands (Flutter, Dart, Git, PowerShell, Python, build tools) are authorized to execute automatically without requiring interactive confirmation for routine actions, debugging, testing, and direct code edits.
- **File & Network Access**: File access within the workspace and necessary internet/API access (e.g. Gemini API, pub.dev packages) are fully permitted.

### 2. Planning & User Confirmation (BẮT BUỘC)
- **Hỏi trước khi thực thi Plan**: Đối với mọi tác vụ cần lên kế hoạch (tính năng mới, tái cấu trúc logic/kiến trúc quan trọng, luồng xử lý mới, hoặc khi người dùng yêu cầu lập plan):
  - Antigravity phải trình bày kế hoạch (Plan / Implementation Plan) rõ ràng, chi tiết các bước.
  - **DỪNG LẠI và hỏi ý kiến người dùng** trước khi tiến hành thực thi (nếu tạo plan artifact thì luôn đặt `RequestFeedback: true`).
  - **KHÔNG tự ý thực thi các bước trong plan** cho đến khi người dùng xác nhận, duyệt kế hoạch hoặc gửi phản hồi đồng ý tiếp tục.

### 3. Development Guidelines
- Always maintain code stability and preserve existing comments, styles, and architecture.
- For Flutter / Dart:
  - Run `flutter pub get` or `flutter analyze` when dependencies or signatures change.
  - Follow MVVM pattern used in the codebase (`lib/models`, `lib/services`, `lib/viewmodels`, `lib/views`).
- When modifying prompt rules or conversation flows (`rule_engine.json`, `llm_service.dart`, etc.), strictly follow charitable evaluation criteria (Quỹ Bông Sen).
