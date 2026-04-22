import 'package:flutter_test/flutter_test.dart';

import 'package:lg_flutter_task2/connections/lg_connection.dart';

// Regression tests for LGConnection.buildHardResetCommand().
//
// Background: hardReset() sends a shell pipeline to lg1 via dartssh2's
// SSHClient.run(). A prior refactor produced the pipeline with
// `parts.join('; ')`. Several parts ended with `&` (backgrounded pkill and
// ssh-pkill), and bash rejects `cmd &; next` as a syntax error:
//
//   bash: -c: line 0: syntax error near unexpected token `;'
//
// The remote shell exited in ~7 ms (observed in /var/log/auth.log) before
// any pkill or relaunch ran. SFTP writes completed, so the UI looked like
// it was working, but Google Earth was never restarted. These tests lock
// the contract so that regression can't happen again.
void main() {
  group('LGConnection.buildHardResetCommand', () {
    test('never emits the bash-syntax-error pattern `&;`', () {
      for (final n in const [1, 2, 3, 4, 5, 8]) {
        final cmd = LGConnection.buildHardResetCommand(n);
        expect(
          cmd,
          isNot(contains('&;')),
          reason: 'n=$n produced `&;` which bash rejects as a syntax error',
        );
      }
    });

    test('uses newline separator between commands (bash-safe after &)', () {
      final cmd = LGConnection.buildHardResetCommand(3);
      expect(cmd, contains('pkill -9 googleearth-bin &\n'),
          reason: 'backgrounded pkill must be terminated by a newline, not `; `');
      expect(cmd.split('\n').length, greaterThan(5),
          reason: 'pipeline should span multiple lines');
    });

    test('backgrounds N pkill commands then waits', () {
      final cmd = LGConnection.buildHardResetCommand(3);
      // lg1 local pkill + lg2 ssh pkill + lg3 ssh pkill = 3 backgrounded lines
      final bgLines = cmd
          .split('\n')
          .where((l) => l.trimRight().endsWith('&'))
          .toList();
      // 3 pkills + 1 local nohup-googleearth-bin (ends with `& disown`)
      // Only the 3 pkill lines end with a bare `&`.
      final bareAmpersandLines =
          bgLines.where((l) => !l.contains('disown')).toList();
      expect(bareAmpersandLines.length, 3,
          reason: '3 pkill lines should be backgrounded for parallel kill');
      expect(cmd.split('\n'), contains('wait'),
          reason: 'must wait for all backgrounded pkills');
    });

    test('relaunches GE on lg1 locally and lg2..lgN via intra-rig SSH', () {
      final cmd = LGConnection.buildHardResetCommand(3);
      final relaunchLine =
          'DISPLAY=:0 nohup /opt/google/earth/pro/googleearth-bin '
          '>/tmp/ge.log 2>&1 < /dev/null & disown';
      expect(cmd, contains(relaunchLine),
          reason: 'lg1 local relaunch must be present');
      expect(cmd, contains('ssh -o BatchMode=yes -o StrictHostKeyChecking=no '
          '-o ConnectTimeout=3 lg@lg2 "$relaunchLine"'),
          reason: 'lg2 relaunch via intra-rig SSH must be present');
      expect(cmd, contains('ssh -o BatchMode=yes -o StrictHostKeyChecking=no '
          '-o ConnectTimeout=3 lg@lg3 "$relaunchLine"'),
          reason: 'lg3 relaunch via intra-rig SSH must be present');
    });

    test('staggers relaunches with 5-second gaps for RAM-tight slaves', () {
      final cmd = LGConnection.buildHardResetCommand(3);
      final sleeps = cmd.split('\n').where((l) => l.startsWith('sleep ')).toList();
      // 1× `sleep 2` after pkill-wait, 2× `sleep 5` between relaunches for n=3.
      expect(sleeps.length, 3,
          reason: 'one sleep 2 + (n-1) sleep 5 for n=3');
      expect(sleeps.where((l) => l == 'sleep 5').length, 2,
          reason: 'N-1 staggers for N screens');
    });

    test('scales with N screens (single-screen rig = no intra-rig SSH)', () {
      final n1 = LGConnection.buildHardResetCommand(1);
      // n=1: just local pkill, wait, sleep, local relaunch. No ssh to lg2/lg3.
      expect(n1, isNot(contains('lg@lg2')));
      expect(n1, isNot(contains('lg@lg3')));
      expect(n1, contains('pkill -9 googleearth-bin &'));
    });
  });
}
