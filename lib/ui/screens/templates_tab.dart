import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/bot_provider.dart';
import '../../models/item.dart';

class TemplatesTab extends StatelessWidget {
  const TemplatesTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('항목 및 응답 설정'),
        actions: [
          IconButton(
            icon: const Icon(Icons.list_alt),
            tooltip: '전체조회 텍스트 설정',
            onPressed: () => _showTotalTemplateDialog(context, context.read<BotProvider>()),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showAddItemDialog(context, context.read<BotProvider>()),
          ),
        ],
      ),
      body: Consumer<BotProvider>(
        builder: (context, bot, child) {
          if (bot.items.isEmpty) {
            return const Center(
              child: Text('등록된 항목이 없습니다.\n우측 상단 + 버튼을 눌러 추가해주세요.'),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: bot.items.length,
            itemBuilder: (context, index) {
              final item = bot.items[index];
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '/[${item.name}] 항목',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo),
                          ),
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit, color: Colors.blue),
                                onPressed: () => _showEditItemDialog(context, bot, item),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () => bot.deleteItem(item.id!),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Text('최대 인원: ${item.maxCapacity}명', style: const TextStyle(color: Colors.grey)),
                      const SizedBox(height: 8),
                      const Text('현재 응답 텍스트:', style: TextStyle(fontWeight: FontWeight.bold)),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        margin: const EdgeInsets.only(top: 4),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Text(
                          item.template.isEmpty ? '기본 템플릿 사용 중' : item.template,
                          maxLines: 5,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: Colors.black87),
                        ),
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

  void _showTotalTemplateDialog(BuildContext context, BotProvider bot) {
    final controller = TextEditingController(text: bot.totalTemplate);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('전체조회 메시지 설정'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('전체조회(/전체조회) 시 전송될 문구입니다.'),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: '메시지 템플릿',
                hintText: '{전체현황} 변수 사용 가능',
                border: OutlineInputBorder(),
              ),
              maxLines: 10,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
          TextButton(
            onPressed: () async {
              await bot.updateTotalTemplate(controller.text);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('저장'),
          ),
        ],
      ),
    );
  }

  void _showEditItemDialog(BuildContext context, BotProvider bot, Item item) {
    final nameController = TextEditingController(text: item.name);
    final capController = TextEditingController(text: item.maxCapacity.toString());
    final templateController = TextEditingController(text: item.template);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${item.name} 수정'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameController, decoration: const InputDecoration(labelText: '항목명')),
              TextField(controller: capController, decoration: const InputDecoration(labelText: '최대 인원'), keyboardType: TextInputType.number),
              const SizedBox(height: 16),
              const Text('응답 텍스트 (공지 템플릿)', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextField(
                controller: templateController,
                decoration: const InputDecoration(
                  hintText: '{날짜}, {인원셋팅}, {현재인원}, {명단} 변수 사용 가능',
                  border: OutlineInputBorder(),
                ),
                maxLines: 12,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
          TextButton(
            onPressed: () async {
              final updated = Item(
                id: item.id,
                name: nameController.text,
                maxCapacity: int.tryParse(capController.text) ?? item.maxCapacity,
                template: templateController.text,
              );
              await bot.updateItem(updated);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('저장'),
          ),
        ],
      ),
    );
  }

  void _showAddItemDialog(BuildContext context, BotProvider bot) {
    final nameController = TextEditingController();
    final capController = TextEditingController(text: '10');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('새 항목 추가'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameController, decoration: const InputDecoration(labelText: '항목명 (예: 메인, 무토)')),
            TextField(controller: capController, decoration: const InputDecoration(labelText: '최대 인원'), keyboardType: TextInputType.number),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
          TextButton(
            onPressed: () async {
              if (nameController.text.isNotEmpty) {
                await bot.addItem(nameController.text, int.tryParse(capController.text) ?? 10);
                if (context.mounted) Navigator.pop(context);
              }
            },
            child: const Text('추가'),
          ),
        ],
      ),
    );
  }
}
