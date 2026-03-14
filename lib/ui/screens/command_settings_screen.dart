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
    final theme = Theme.of(context);
    
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('명령어 단어 설정'),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF643921).withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF643921).withOpacity(0.1)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: theme.colorScheme.primary, size: 20),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          '카카오톡에서 사용할 단어를 설정하세요.\n설정한 단어 앞에 /[항목명]을 붙여서 사용합니다.',
                          style: TextStyle(color: Color(0xFF643921), fontSize: 13, height: 1.5),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                _buildCmdField('예약 명령어', '예: 예약, 등록, ㄱㄱ', 'reserve'),
                _buildCmdField('취소 명령어', '예: 예약취소, 취소, ㄴㄴ', 'cancel'),
                _buildCmdField('조회 명령어', '예: 조회, 명단, ㅎㅇ', 'status'),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Row(
                    children: [
                      Text('관리자 전용 명령어', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF968954))),
                      SizedBox(width: 8),
                      Expanded(child: Divider(color: Color(0xFF968954), thickness: 0.5)),
                    ],
                  ),
                ),
                _buildCmdField('초기화 명령어', '예: 초기화, 비우기', 'reset'),
                _buildCmdField('최대인원 변경', '예: 세팅최대, 인원변경', 'max'),
                _buildCmdField('텍스트변경', '예: 텍스트변경, 문구수정', 'template'),
                const Divider(height: 48),
                _buildCmdField('전체조회 (/[단어])', '예: 전체조회, 전체현황', 'total'),
                const SizedBox(height: 40),
              ],
            ),
          ),
          // 고정된 대형 저장 버튼
          Container(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
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
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF643921),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: const Text('명령어 설정 저장하기', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCmdField(String label, String hint, String key) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: TextField(
        controller: _controllers[key],
        cursorColor: const Color(0xFF643921),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Color(0xFF643921), fontWeight: FontWeight.w500),
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
          filled: true,
          fillColor: Colors.grey.shade50,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade200),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFF643921), width: 1.5),
          ),
          prefixText: key == 'total' ? '/' : '/[항목] ',
          prefixStyle: const TextStyle(color: Color(0xFF968954), fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
