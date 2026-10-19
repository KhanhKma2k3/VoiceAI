import 'api_service.dart';

/// Trước đây class này tự gọi http.post trực tiếp tới /chat mà KHÔNG gắn
/// token đăng nhập -> luôn bị 401 sau khi backend bật xác thực JWT bắt buộc.
/// Giờ chuyển hẳn sang gọi qua ApiService (nơi duy nhất biết cách đính kèm
/// header Authorization), để tránh viết trùng logic gọi API ở 2 nơi.
class AiChatService {
  Future<String?> sendMessage(String text) async {
    return await ApiService.sendMessage(text);
  }
}
