import 'package:flutter/material.dart';
import '../services/api_service.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late Future<List<dynamic>> _historyFuture;

  @override
  void initState() {
    super.initState();
    _refreshHistory();
  }

  void _refreshHistory() {
    setState(() {
      _historyFuture = ApiService.getHistory();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Lịch sử trò chuyện"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshHistory,
          ),
        ],
      ),
      body: FutureBuilder<List<dynamic>>(
        future: _historyFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(
              child: Text(
                "Chưa có lịch sử trò chuyện nào.",
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            );
          }

          final historyList = snapshot.data!;

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: historyList.length,
            itemBuilder: (context, index) {
              final item = historyList[index];
              final userMessage = item['user_message'] ?? '';
              final botReply = item['bot_reply'] ?? '';
              final createdAt = item['created_at'] ?? '';

              return Card(
                margin: const EdgeInsets.symmetric(vertical: 8),
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Thời gian tạo
                      if (createdAt.isNotEmpty)
                        Text(
                          createdAt.toString().replaceAll('T', ' ').split('.').first,
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      const SizedBox(height: 8),
                      // Câu hỏi của người dùng
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.person, color: Colors.blue, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              userMessage,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 16),
                      // Câu trả lời của Bot
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.smart_toy, color: Colors.green, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              botReply,
                              style: const TextStyle(fontSize: 15),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}