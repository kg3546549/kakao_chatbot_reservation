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
            icon: const Icon(Icons.list_alt, color: Color(0xFF40916C)),
            tooltip: '전체조회 텍스트 설정',
            onPressed: () => _showTotalTemplateDialog(context, context.read<BotProvider>()),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline, color: Color(0xFF40916C)),
            onPressed: () => _showAddItemDialog(context, context.read<BotProvider>()),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Consumer<BotProvider>(
        builder: (context, bot, child) {
          if (bot.items.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.edit_note, size: 60, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  const Text('등록된 항목이 없습니다.\n우측 상단 + 버튼을 눌러 추가해주세요.', 
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: bot.items.length,
            itemBuilder: (context, index) {
              final item = bot.items[index];
              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.03),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 4,
                                height: 20,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF40916C),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                '/${item.name}',
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1B4332)),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined, color: Color(0xFF40916C), size: 20),
                                onPressed: () => _showEditItemDialog(context, bot, item),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                onPressed: () => _showDeleteConfirm(context, bot, item),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('최대 정원: ${item.maxCapacity}명', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                      const SizedBox(height: 16),
                      const Text('응답 메시지 프리뷰', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8F9FA),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade100),
                        ),
                        child: Text(
                          item.template.isEmpty ? '기본 템플릿 사용 중' : item.template,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: Colors.black87, height: 1.4),
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

  void _showDeleteConfirm(BuildContext context, BotProvider bot, Item item) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('항목 삭제'),
        content: Text('/${item.name} 항목과 관련된 모든 예약 정보가 사라집니다.\n정말 삭제하시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소', style: TextStyle(color: Colors.grey))),
          TextButton(
            onPressed: () {
              bot.deleteItem(item.id!);
              Navigator.pop(context);
            },
            child: const Text('삭제하기', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showTotalTemplateDialog(BuildContext context, BotProvider bot) {
    final controller = TextEditingController(text: bot.totalTemplate);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('전체조회 메시지 설정', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('모든 항목의 현황을 보여주는 문구입니다.', style: TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: '{전체현황} 변수 사용 가능',
                filled: true,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF40916C))),
              ),
              maxLines: 8,
              style: const TextStyle(fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () async {
              await bot.updateTotalTemplate(controller.text);
              if (context.mounted) Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(minimumSize: const Size(80, 40)),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('/${item.name} 수정', style: const TextStyle(fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController, 
                decoration: const InputDecoration(labelText: '항목명', labelStyle: TextStyle(fontSize: 13)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: capController, 
                decoration: const InputDecoration(labelText: '최대 정원', labelStyle: TextStyle(fontSize: 13)),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 24),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('응답 텍스트 (공지 템플릿)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: templateController,
                decoration: InputDecoration(
                  hintText: '{날짜}, {인원셋팅}, {현재인원}, {명단} 변수 사용',
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
                maxLines: 10,
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
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
            style: ElevatedButton.styleFrom(minimumSize: const Size(80, 40)),
            child: const Text('저장'),
          ),
        ],
      ),
    );
  }

  void _showAddItemDialog(BuildContext context, BotProvider bot) {
    final nameController = TextEditingController();
    final capController = TextEditingController(text: '15');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('새 항목 추가', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController, 
              decoration: const InputDecoration(labelText: '항목명 (예: 메인, 무토)', labelStyle: TextStyle(fontSize: 13)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: capController, 
              decoration: const InputDecoration(labelText: '최대 정원', labelStyle: TextStyle(fontSize: 13)),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.isNotEmpty) {
                await bot.addItem(nameController.text, int.tryParse(capController.text) ?? 15);
                if (context.mounted) Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(minimumSize: const Size(80, 40)),
            child: const Text('추가'),
          ),
        ],
      ),
    );
  }
}
