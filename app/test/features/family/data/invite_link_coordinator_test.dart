import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/features/family/data/invite_link_coordinator.dart';

void main() {
  test('accepts only the verified permanent family-link route', () async {
    final coordinator = InviteLinkCoordinator(
      _InviteUriSource(const Stream<Uri>.empty(), _familyLink),
    );

    final event = await coordinator.takeInitialLink();

    expect(event, isA<ValidFamilyJoinLinkEvent>());
    expect((event! as ValidFamilyJoinLinkEvent).link.code.display, 'K7M4-P2Q8');
    expect(event.toString(), 'ValidFamilyJoinLinkEvent(<redacted>)');
    await coordinator.dispose();
  });

  test(
    'redacts malformed family namespace links and ignores every other route',
    () async {
      final stream = StreamController<Uri>();
      final coordinator = InviteLinkCoordinator(
        _InviteUriSource(stream.stream, null),
      );
      final events = <InviteLinkEvent>[];
      final subscription = coordinator.events.listen(events.add);
      await coordinator.resolveInitialLink();

      stream
        ..add(Uri.parse('keepers://auth-callback?code=authorization-code'))
        ..add(Uri.parse('keepers://join?v=1&i=legacy-invite&t=secret&s=secret'))
        ..add(Uri.parse('https://keepers.app/f/K7M4-P2Q8'))
        ..add(Uri.parse('https://join.keepers.app/help'))
        ..add(
          Uri.parse('https://join.keepers.app/f/K7M4-P2Q8?token=do-not-log'),
        )
        ..add(Uri.parse('https://join.keepers.app/f/INVALID'));
      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(2));
      expect(events, everyElement(isA<MalformedFamilyJoinLinkEvent>()));
      expect(
        events.map((event) => event.toString()),
        everyElement('MalformedFamilyJoinLinkEvent()'),
      );
      expect('$events', isNot(contains('do-not-log')));
      expect('$events', isNot(contains('K7M4')));
      await subscription.cancel();
      await coordinator.dispose();
      await stream.close();
    },
  );

  test(
    'coalesces stream-first cold delivery but permits a deliberate reopen',
    () async {
      final stream = StreamController<Uri>();
      final initialUri = Completer<Uri?>();
      final coordinator = InviteLinkCoordinator(
        _DelayedInviteUriSource(stream.stream, initialUri.future),
      );
      final warm = <InviteLinkEvent>[];
      final subscription = coordinator.events.listen(warm.add);
      final initial = coordinator.takeInitialLink();

      stream.add(_familyLink);
      await Future<void>.delayed(Duration.zero);
      initialUri.complete(_familyLink);

      expect(await initial, isA<ValidFamilyJoinLinkEvent>());
      await Future<void>.delayed(Duration.zero);
      expect(warm, isEmpty);

      stream.add(_familyLink);
      await Future<void>.delayed(Duration.zero);
      expect(warm, [isA<ValidFamilyJoinLinkEvent>()]);

      await subscription.cancel();
      await coordinator.dispose();
      await stream.close();
    },
  );

  test(
    'coalesces one late cold duplicate without permanently seeing the code',
    () async {
      final stream = StreamController<Uri>();
      final coordinator = InviteLinkCoordinator(
        _InviteUriSource(stream.stream, _familyLink),
      );
      final warm = <InviteLinkEvent>[];
      final subscription = coordinator.events.listen(warm.add);

      expect(
        await coordinator.takeInitialLink(),
        isA<ValidFamilyJoinLinkEvent>(),
      );

      stream.add(_familyLink);
      await Future<void>.delayed(Duration.zero);
      expect(warm, isEmpty);

      stream.add(_familyLink);
      await Future<void>.delayed(Duration.zero);
      expect(warm, [isA<ValidFamilyJoinLinkEvent>()]);

      await subscription.cancel();
      await coordinator.dispose();
      await stream.close();
    },
  );

  test(
    'releasing the cold guard permits a reopen without a prior duplicate',
    () async {
      final stream = StreamController<Uri>();
      final coordinator = InviteLinkCoordinator(
        _InviteUriSource(stream.stream, _familyLink),
      );
      final warm = <InviteLinkEvent>[];
      final subscription = coordinator.events.listen(warm.add);

      expect(
        await coordinator.takeInitialLink(),
        isA<ValidFamilyJoinLinkEvent>(),
      );
      coordinator.releaseColdDeliveryGuard();
      stream.add(_familyLink);
      await Future<void>.delayed(Duration.zero);

      expect(warm, [isA<ValidFamilyJoinLinkEvent>()]);
      await subscription.cancel();
      await coordinator.dispose();
      await stream.close();
    },
  );

  test('applies the same bounded cold guard to malformed links', () async {
    final stream = StreamController<Uri>();
    final malformed = Uri.parse(
      'https://join.keepers.app/f/K7M4-P2Q8?token=do-not-log',
    );
    final coordinator = InviteLinkCoordinator(
      _InviteUriSource(stream.stream, malformed),
    );
    final warm = <InviteLinkEvent>[];
    final subscription = coordinator.events.listen(warm.add);

    expect(
      await coordinator.takeInitialLink(),
      isA<MalformedFamilyJoinLinkEvent>(),
    );

    stream.add(malformed);
    await Future<void>.delayed(Duration.zero);
    expect(warm, isEmpty);

    stream.add(malformed);
    await Future<void>.delayed(Duration.zero);
    expect(warm, [isA<MalformedFamilyJoinLinkEvent>()]);
    expect('$warm', isNot(contains('do-not-log')));

    await subscription.cancel();
    await coordinator.dispose();
    await stream.close();
  });

  test(
    'keeps the initial URI authoritative ahead of a distinct buffered event',
    () async {
      final initialUri = Completer<Uri?>();
      final stream = StreamController<Uri>();
      final coordinator = InviteLinkCoordinator(
        _DelayedInviteUriSource(stream.stream, initialUri.future),
      );
      final warm = <InviteLinkEvent>[];
      final subscription = coordinator.events.listen(warm.add);
      final resolution = coordinator.takeInitialLink();
      stream.add(_familyLinkFor('1111-1111'));
      initialUri.complete(_familyLinkFor('2222-2222'));

      final cold = await resolution as ValidFamilyJoinLinkEvent;
      await Future<void>.delayed(Duration.zero);

      expect(cold.link.code.normalized, '22222222');
      expect(
        (warm.single as ValidFamilyJoinLinkEvent).link.code.normalized,
        '11111111',
      );
      await subscription.cancel();
      await coordinator.dispose();
      await stream.close();
    },
  );

  test('bounds links arriving while the initial lookup is pending', () async {
    final initialUri = Completer<Uri?>();
    final stream = StreamController<Uri>();
    final coordinator = InviteLinkCoordinator(
      _DelayedInviteUriSource(stream.stream, initialUri.future),
    );
    final warm = <InviteLinkEvent>[];
    final subscription = coordinator.events.listen(warm.add);
    final resolution = coordinator.takeInitialLink();

    for (var value = 0; value < 12; value += 1) {
      stream.add(_familyLinkFor(value.toString().padLeft(8, '0')));
    }
    await Future<void>.delayed(Duration.zero);
    initialUri.complete(null);

    final cold = await resolution as ValidFamilyJoinLinkEvent;
    await Future<void>.delayed(Duration.zero);
    final deliveredCodes = <String>[
      cold.link.code.normalized,
      ...warm.map(
        (event) => (event as ValidFamilyJoinLinkEvent).link.code.normalized,
      ),
    ];

    expect(deliveredCodes, hasLength(8));
    expect(deliveredCodes.first, '00000004');
    expect(deliveredCodes.last, '00000011');
    await subscription.cancel();
    await coordinator.dispose();
    await stream.close();
  });

  test('subscribes before an initial lookup is allowed to finish', () async {
    final initial = Completer<Uri?>();
    var listened = false;
    final stream = StreamController<Uri>(onListen: () => listened = true);
    final coordinator = InviteLinkCoordinator(
      _DelayedInviteUriSource(stream.stream, initial.future),
    );

    final resolution = coordinator.resolveInitialLink();
    expect(listened, isTrue);
    initial.complete(null);
    await resolution;
    await coordinator.dispose();
    await stream.close();
  });

  test('consuming the initial link keeps public resolution one-shot', () async {
    final source = _CountingInviteUriSource(_familyLink);
    final coordinator = InviteLinkCoordinator(source);

    expect(
      await coordinator.takeInitialLink(),
      isA<ValidFamilyJoinLinkEvent>(),
    );
    expect(await coordinator.takeInitialLink(), isNull);
    expect(await coordinator.resolveInitialLink(), isNull);
    expect(source.listenCount, 1);
    expect(source.initialReadCount, 1);

    await coordinator.dispose();
  });
}

final _familyLink = _familyLinkFor('K7M4-P2Q8');

Uri _familyLinkFor(String code) =>
    Uri.parse('https://join.keepers.app/f/$code');

final class _InviteUriSource implements InviteUriSource {
  const _InviteUriSource(this.uriLinkStream, this.initial);

  @override
  final Stream<Uri> uriLinkStream;
  final Uri? initial;

  @override
  Future<Uri?> getInitialUri() async => initial;
}

final class _DelayedInviteUriSource implements InviteUriSource {
  const _DelayedInviteUriSource(this.uriLinkStream, this._initial);

  @override
  final Stream<Uri> uriLinkStream;
  final Future<Uri?> _initial;

  @override
  Future<Uri?> getInitialUri() => _initial;
}

final class _CountingInviteUriSource implements InviteUriSource {
  _CountingInviteUriSource(this._initial) {
    _stream = Stream<Uri>.multi((_) => listenCount += 1);
  }

  final Uri? _initial;
  late final Stream<Uri> _stream;
  var listenCount = 0;
  var initialReadCount = 0;

  @override
  Stream<Uri> get uriLinkStream => _stream;

  @override
  Future<Uri?> getInitialUri() async {
    initialReadCount += 1;
    return _initial;
  }
}
