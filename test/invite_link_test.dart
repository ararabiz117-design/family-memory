import 'package:flutter_test/flutter_test.dart';

import 'package:family_memory/auth_flow.dart';

void main() {
  const token = 'abcdefghijklmnopqrstuvwxyzABCDEFGHJKLMNPQRS';

  test('アプリ用招待リンクとWeb招待リンクからtokenを受け取る', () {
    expect(
      inviteTokenFromUri(Uri.parse('familymemory://invite?token=$token')),
      token,
    );
    expect(
      inviteTokenFromUri(
        Uri.parse('https://beta.example.invalid/invite?token=$token'),
      ),
      token,
    );
  });

  test('不正なhost、path、長さ、余計な文字を拒否する', () {
    expect(
      inviteTokenFromUri(Uri.parse('familymemory://other?token=$token')),
      isNull,
    );
    expect(
      inviteTokenFromUri(
        Uri.parse('https://beta.example.invalid/other?token=$token'),
      ),
      isNull,
    );
    expect(
      inviteTokenFromUri(Uri.parse('familymemory://invite?token=short')),
      isNull,
    );
    expect(
      inviteTokenFromUri(
        Uri.parse('familymemory://invite?token=${token.substring(0, 42)}!'),
      ),
      isNull,
    );
  });
}
