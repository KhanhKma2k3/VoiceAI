import logging

from config import settings

logger = logging.getLogger(__name__)

_SYSTEM_INSTRUCTION = (
    "Bạn là một trợ lý ảo giọng nói tiếng Việt thông minh, thân thiện "
    "và trả lời ngắn gọn, súc tích."
)

# Trước đây dùng 1 "chat_session" toàn cục dùng chung cho MỌI người dùng và
# MỌI request -> gây 2 lỗi:
#   1) Thư viện google-genai đóng kết nối ngầm sau một thời gian dùng theo
#      kiểu session dài hạn trong app đa luồng như FastAPI -> lỗi
#      "Cannot send a request, as the client has been closed."
#   2) Nghiêm trọng hơn: TẤT CẢ người dùng app chia sẻ chung 1 phiên hội
#      thoại Gemini -> câu hỏi/trả lời của người này có thể lẫn vào ngữ
#      cảnh của người khác.
#
# Giờ mỗi lần gọi tạo 1 client mới (rẻ, không tốn network cho tới khi thực
# sự generate) và gọi generate_content() không trạng thái (stateless) -
# an toàn với nhiều luồng, không rò rỉ ngữ cảnh giữa các user.


def ask_gemini(prompt: str) -> str:
    try:
        from google import genai
        from google.genai import types

        client = genai.Client(api_key=settings.GEMINI_API_KEY)
        response = client.models.generate_content(
            model=settings.GEMINI_MODEL,
            contents=prompt,
            config=types.GenerateContentConfig(
                system_instruction=_SYSTEM_INSTRUCTION,
                max_output_tokens=1000,
            ),
        )
        return response.text.strip() if response.text else "Tôi không thể đưa ra câu trả lời lúc này."
    except Exception as e:
        error_msg = str(e)
        logger.error("Loi Gemini: %s", error_msg)

        if "429" in error_msg or "RESOURCE_EXHAUSTED" in error_msg:
            return "Hệ thống AI đang quá tải lượt hỏi trong ngày. Vui lòng thử lại sau ít phút!"

        return "Xin lỗi, hệ thống AI gặp sự cố kết nối."
