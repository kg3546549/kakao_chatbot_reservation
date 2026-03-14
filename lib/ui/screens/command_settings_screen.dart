import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/bot_provider.dart';

class CommandSettingsScreen extends StatefulWidget {
  const CommandSettingsScreen({super.key});

  @override
  State<CommandSettingsScreen> createState() => _CommandSettingsScreenState();
}

class _CommandSettingsScreenState extends State<CommandSettingsScreen> {
  final Map<String, TextEditingController> _controllers = {};

  @override
  void initState() {
    super.initState();
    final bot = context.read<BotProvider>();
    _controllers['reserve'] = TextEditingController(text: bot.cmdReserve);
    _controllers['cancel'] = TextEditingController(text: bot.cmdCancel);
    _controllers['status'] = TextEditingController(text: bot.cmdStatus);
    _controllers['reset'] = TextEditingController(text: bot.cmdReset);
    _controllers['max'] = TextEditingController(text: bot.cmdMax);
    _controllers['template'] = TextEditingController(text: bot.cmdTemplate);
    _controllers['total'] = TextEditingController(text: bot.cmdTotal);
  }

  @override
  void dispose() {
    for (var controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('명령어 단어 설정'),
        actions: [
          TextButton(
            onPressed: () async {
              await context.read<BotProvider>().updateCommands(
                reserve: _controllers['reserve']!.text,
                cancel: _controllers['cancel']!.text,
                status: _controllers['status']!.text,
                reset: _controllers['reset']!.text,
                max: _controllers['max']!.text,
                template: _controllers['template']!.text,
                total: _controllers['total']!.text,
              );
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('명령어 설정이 저장되었습니다.')),
                );
                Navigator.pop(context);
              }
            },
            child: const Text('저장', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            '카카오톡에서 사용할 단어를 설정하세요.\n설정한 단어 앞에 /[항목명]을 붙여서 사용합니다.',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 24),
          _buildCmdField('예약 명령어', '예: 예약, 등록, ㄱㄱ', 'reserve'),
          _buildCmdField('취소 명령어', '예: 예약취소, 취소, ㄴㄴ', 'cancel'),
          _buildCmdField('조회 명령어', '예: 조회, 명단, ㅎㅇ', 'status'),
          const Divider(height: 40),
          const Text('관리자 전용 명령어', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
          const SizedBox(height: 16),
          _buildCmdField('초기화 명령어', '예: 초기화, 비우기', 'reset'),
          _buildCmdField('최대인원 변경', '예: 세팅최대, 인원변경', 'max'),
          _buildCmdField('텍스트변경', '예: 텍스트변경, 문구수정', 'template'),
          const Divider(height: 40),
          _buildCmdField('전체조회 (/[단어])', '예: 전체조회, 전체현황', 'total'),
        ],
      ),
    );
  }

  Widget _buildCmdField(String label, String hint, String key) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: _controllers[key],
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
          prefixText: key == 'total' ? '/' : '/[항목] ',
          prefixStyle: const TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
