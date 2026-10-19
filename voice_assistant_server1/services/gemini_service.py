import os
from google import genai
from google.genai import types

#API_KEY = "AQ.Ab8RN6KNwzH7TndwLNQ2LLKHvKawxCYCIbaTBe2c9enQVADcDQ"
API_KEY = os.getenv("GEMINI_API_KEY")
# 1. Khởi tạo Client
client = genai.Client(api_key=API_KEY)

# 2. Khởi tạo Chat Session duy trì hội thoại
chat_session = client.chats.create(
    model="gemini-3.8-flash",
    config=types.GenerateContentConfig(
        system_instruction="Bạn là một trợ lý ảo giọng nói tiếng Việt thông minh, thân thiện và trả lời ngắn gọn, súc tích.",
        max_output_tokens=1000,
    )
)

def ask_gemini(prompt: str) -> str:
    try:
        response = chat_session.send_message(prompt)
        return response.text.strip() if response.text else "Tôi không thể đưa ra câu trả lời lúc này."
    except Exception as e:
        error_msg = str(e)
        print(f"❌ LỖI GEMINI CHI TIẾT: {error_msg}")
        
        if "429" in error_msg or "RESOURCE_EXHAUSTED" in error_msg:
            return "Hệ thống AI đang quá tải lượt hỏi trong ngày. Vui lòng thử lại sau ít phút!"
            
        return "Xin lỗi, hệ thống AI gặp sự cố kết nối."