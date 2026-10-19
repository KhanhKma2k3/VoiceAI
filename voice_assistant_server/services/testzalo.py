# Chạy script này TRÊN MÁY SERVER (nơi có thể gọi ra Internet tới Zalo AI).
# Mục đích: gọi thẳng Zalo AI API với 2 mức speed khác nhau (0.80 và 1.20)
# để nghe thử xem tốc độ đọc THỰC SỰ có đổi hay không -- tách hẳn khỏi toàn
# bộ app Flutter/FastAPI để loại trừ mọi nghi ngờ ở các tầng khác.
#
# Cách chạy:
#   1. pip install requests
#   2. Sửa ZALO_API_KEY bên dưới thành key thật của bạn
#   3. python test_zalo_speed.py
#   4. Nghe file zalo_speed_080.mp3 và zalo_speed_120.mp3, so sánh tốc độ đọc

import time
import requests

ZALO_API_KEY = "aL7ESnlFR14bINBe3twyJxmchhMIymGb"  # <-- thay bằng key thật của bạn nếu khác
TEXT = "Xin chào, đây là bài kiểm tra tốc độ đọc của giọng Zalo AI"
SPEAKER_ID = "1"


def synthesize(speed: float, out_path: str):
    headers = {"apikey": ZALO_API_KEY}
    data = {"input": TEXT, "speaker_id": SPEAKER_ID, "speed": f"{speed:.2f}"}

    print(f"\n=== Gọi Zalo AI với speed={speed:.2f} ===")
    response = requests.post(
        "https://api.zalo.ai/v1/tts/synthesize", headers=headers, data=data, timeout=15
    )
    print("HTTP status:", response.status_code)
    res_data = response.json()
    print("Response JSON:", res_data)

    if res_data.get("error_code") != 0:
        print("!!! Zalo trả lỗi, không thể tạo audio. Xem error_message ở trên.")
        return

    async_url = res_data["data"]["url"]
    for attempt in range(15):
        time.sleep(0.8)
        audio_res = requests.get(async_url, timeout=15)
        if audio_res.status_code == 200:
            with open(out_path, "wb") as f:
                f.write(audio_res.content)
            print(f"-> Đã lưu: {out_path} ({len(audio_res.content)} bytes)")
            return
        print(f"   (lần {attempt + 1}) audio chưa sẵn sàng, status={audio_res.status_code}")

    print("!!! Hết thời gian chờ, audio vẫn chưa sẵn sàng.")


if __name__ == "__main__":
    synthesize(0.80, "zalo_speed_080.mp3")
    synthesize(1.20, "zalo_speed_120.mp3")
    print("\nXong. Hãy nghe và so sánh 2 file zalo_speed_080.mp3 và zalo_speed_120.mp3.")