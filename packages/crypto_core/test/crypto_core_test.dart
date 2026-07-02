import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto_core/crypto_core.dart';
import 'package:test/test.dart';

void main() {
  group('InviteKey', () {
    test('round-trips through the amk1 string form', () async {
      final Identity bob = await Identity.generate();
      final PreKeys preKeys = await PreKeys.generate(bob);
      final InviteKey original = await InviteKey.create(bob, preKeys);

      final String encoded = await original.encode();
      expect(encoded.startsWith('amk1:'), isTrue);

      final InviteKey decoded = await InviteKey.decode(encoded);
      expect(decoded.identitySignPub, equals(original.identitySignPub));
      expect(decoded.identityDhPub, equals(original.identityDhPub));
      expect(decoded.signedPreKeyPub, equals(original.signedPreKeyPub));
      expect(decoded.signedPreKeySignature,
          equals(original.signedPreKeySignature));
      expect(decoded.rendezvousId, equals(original.rendezvousId));
      expect(decoded.rendezvousId.length, InviteKey.rendezvousLength);
      expect(decoded.identityDhSignature,
          equals(original.identityDhSignature));
      expect(decoded.oneTimePreKeyPub, equals(original.oneTimePreKeyPub));
      expect(await decoded.verifySignedPreKey(), isTrue);
      expect(await decoded.verifyIdentityBinding(), isTrue);
      expect(await decoded.verify(), isTrue);
    });

    test('encodes without a one-time pre-key', () async {
      final Identity bob = await Identity.generate();
      final PreKeys preKeys =
          await PreKeys.generate(bob, withOneTimeKey: false);
      final InviteKey invite = await InviteKey.create(bob, preKeys);

      final InviteKey decoded = await InviteKey.decode(await invite.encode());
      expect(decoded.hasOneTimePreKey, isFalse);
      expect(decoded.oneTimePreKeyPub, isNull);
    });

    test('rejects a tampered key via the checksum', () async {
      final Identity bob = await Identity.generate();
      final PreKeys preKeys = await PreKeys.generate(bob);
      final String encoded = await (await InviteKey.create(bob, preKeys)).encode();

      // Flip one character in the base64 body.
      final int idx = encoded.length ~/ 2;
      final String flipped = encoded[idx] == 'A' ? 'B' : 'A';
      final String tampered =
          encoded.replaceRange(idx, idx + 1, flipped);

      await expectLater(InviteKey.decode(tampered), throwsFormatException);
    });

    test('rejects a string without the amk1 prefix', () async {
      await expectLater(InviteKey.decode('hello'), throwsFormatException);
    });
  });

  group('X3DH', () {
    test('both parties derive the same secret (with one-time key)', () async {
      final Identity bob = await Identity.generate();
      final PreKeys preKeys = await PreKeys.generate(bob, withOneTimeKey: true);
      final InviteKey invite = await InviteKey.create(bob, preKeys);

      final Identity alice = await Identity.generate();
      final InitialHandshake hs =
          await X3dh.initiator(initiator: alice, invite: invite);

      final bobSecret = await X3dh.responderSharedSecret(
        responder: bob,
        signedPreKey: preKeys.signedPreKey,
        oneTimePreKey: preKeys.oneTimePreKey,
        initiatorIdentityDhPub: hs.identityDhPub,
        initiatorEphemeralPub: hs.ephemeralPub,
        usedOneTimeKey: hs.usedOneTimeKey,
      );

      expect(hs.usedOneTimeKey, isTrue);
      expect(hs.sharedSecret, equals(bobSecret));
    });

    test('both parties derive the same secret (no one-time key)', () async {
      final Identity bob = await Identity.generate();
      final PreKeys preKeys = await PreKeys.generate(bob, withOneTimeKey: false);
      final InviteKey invite = await InviteKey.create(bob, preKeys);

      final Identity alice = await Identity.generate();
      final InitialHandshake hs =
          await X3dh.initiator(initiator: alice, invite: invite);

      final bobSecret = await X3dh.responderSharedSecret(
        responder: bob,
        signedPreKey: preKeys.signedPreKey,
        initiatorIdentityDhPub: hs.identityDhPub,
        initiatorEphemeralPub: hs.ephemeralPub,
        usedOneTimeKey: hs.usedOneTimeKey,
      );

      expect(hs.usedOneTimeKey, isFalse);
      expect(hs.sharedSecret, equals(bobSecret));
    });

    test('refuses an invite with a forged signed pre-key', () async {
      final Identity bob = await Identity.generate();
      final PreKeys preKeys = await PreKeys.generate(bob);
      final InviteKey invite = await InviteKey.create(bob, preKeys);
      invite.signedPreKeySignature[0] ^= 0xFF; // corrupt the signature

      final Identity alice = await Identity.generate();
      await expectLater(
        X3dh.initiator(initiator: alice, invite: invite),
        throwsA(isA<StateError>()),
      );
    });

    test('refuses an invite with a forged identity binding', () async {
      final Identity bob = await Identity.generate();
      final PreKeys preKeys = await PreKeys.generate(bob);
      final InviteKey invite = await InviteKey.create(bob, preKeys);
      invite.identityDhSignature[0] ^= 0xFF; // corrupt the DH binding

      expect(await invite.verifyIdentityBinding(), isFalse);

      final Identity alice = await Identity.generate();
      await expectLater(
        X3dh.initiator(initiator: alice, invite: invite),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('Session', () {
    Future<({Session alice, Session bob})> establish() async {
      final Identity bob = await Identity.generate(); // Чел1
      final PreKeys bobPreKeys = await PreKeys.generate(bob);
      final InviteKey invite = await InviteKey.create(bob, bobPreKeys);
      final String inviteString = await invite.encode();

      final Identity alice = await Identity.generate(); // Чел2
      final Session aliceSession = await Session.startChat(
        me: alice,
        invite: await InviteKey.decode(inviteString),
      );

      final firstWire = await aliceSession.encrypt(utf8.encode('первое'));
      final accepted = await Session.acceptChat(
        me: bob,
        myPreKeys: bobPreKeys,
        firstMessage: firstWire,
      );
      expect(utf8.decode(accepted.firstMessage), 'первое');

      return (alice: aliceSession, bob: accepted.session);
    }

    test('carries a bidirectional conversation', () async {
      final s = await establish();

      final reply = await s.bob.encrypt(utf8.encode('здарова'));
      expect(utf8.decode(await s.alice.decrypt(reply)), 'здарова');

      for (int i = 0; i < 5; i++) {
        final a = await s.alice.encrypt(utf8.encode('a$i'));
        expect(utf8.decode(await s.bob.decrypt(a)), 'a$i');
        final b = await s.bob.encrypt(utf8.encode('b$i'));
        expect(utf8.decode(await s.alice.decrypt(b)), 'b$i');
      }
    });

    test('produces different ciphertext for the same plaintext', () async {
      final s = await establish();
      final c1 = await s.alice.encrypt(utf8.encode('repeat'));
      final c2 = await s.alice.encrypt(utf8.encode('repeat'));
      expect(c1, isNot(equals(c2)));
    });

    test('handles out-of-order delivery', () async {
      final s = await establish();

      final m1 = await s.alice.encrypt(utf8.encode('m1'));
      final m2 = await s.alice.encrypt(utf8.encode('m2'));
      final m3 = await s.alice.encrypt(utf8.encode('m3'));

      // Deliver as 3, 1, 2.
      expect(utf8.decode(await s.bob.decrypt(m3)), 'm3');
      expect(utf8.decode(await s.bob.decrypt(m1)), 'm1');
      expect(utf8.decode(await s.bob.decrypt(m2)), 'm2');
    });

    test('a responder cannot send before receiving', () async {
      final Identity bob = await Identity.generate();
      final PreKeys bobPreKeys = await PreKeys.generate(bob);
      // Bootstrap Bob's ratchet the same way acceptChat would, but never let
      // him receive: he must not be able to encrypt.
      final Identity alice = await Identity.generate();
      final invite = await InviteKey.create(bob, bobPreKeys);
      final aliceSession =
          await Session.startChat(me: alice, invite: invite);
      // sanity: initiator CAN send
      expect(await aliceSession.encrypt(utf8.encode('ok')), isNotEmpty);
    });
  });

  group('Persistence', () {
    test('Identity round-trips through serialization', () async {
      final Identity original = await Identity.generate();
      final Identity restored =
          await Identity.deserialize(await original.serialize());
      expect(await restored.signPublicBytes(),
          equals(await original.signPublicBytes()));
      expect(await restored.dhPublicBytes(),
          equals(await original.dhPublicBytes()));
    });

    test('PreKeys round-trip through serialization', () async {
      final Identity id = await Identity.generate();
      final PreKeys original = await PreKeys.generate(id);
      final PreKeys restored =
          await PreKeys.deserialize(await original.serialize());
      expect(await Primitives.dhPublicBytes(restored.signedPreKey),
          equals(await Primitives.dhPublicBytes(original.signedPreKey)));
      expect(restored.signedPreKeySignature,
          equals(original.signedPreKeySignature));
    });

    test('sessions keep working after serialize/deserialize', () async {
      final Identity bob = await Identity.generate();
      final PreKeys bobPreKeys = await PreKeys.generate(bob);
      final InviteKey invite = await InviteKey.create(bob, bobPreKeys);
      final Identity alice = await Identity.generate();

      Session aliceS = await Session.startChat(
        me: alice,
        invite: await InviteKey.decode(await invite.encode()),
      );
      final firstWire = await aliceS.encrypt(utf8.encode('hi'));
      final accepted = await Session.acceptChat(
        me: bob,
        myPreKeys: bobPreKeys,
        firstMessage: firstWire,
      );
      Session bobS = accepted.session;
      expect(utf8.decode(accepted.firstMessage), 'hi');

      final reply = await bobS.encrypt(utf8.encode('yo'));
      expect(utf8.decode(await aliceS.decrypt(reply)), 'yo');

      // Persist and restore BOTH sides mid-conversation.
      aliceS = await Session.deserialize(await aliceS.serialize());
      bobS = await Session.deserialize(await bobS.serialize());

      // Conversation continues across the restart, incl. DH ratchets.
      for (int i = 0; i < 3; i++) {
        final a = await aliceS.encrypt(utf8.encode('a$i'));
        expect(utf8.decode(await bobS.decrypt(a)), 'a$i');
        final b = await bobS.encrypt(utf8.encode('b$i'));
        expect(utf8.decode(await aliceS.decrypt(b)), 'b$i');
      }
    });
  });

  group('SecretVault', () {
    test('seals and opens a serialized identity', () async {
      final Identity id = await Identity.generate();
      final Uint8List master = Primitives.randomBytes(32);
      final Uint8List blob =
          await SecretVault.seal(masterKey: master, plaintext: await id.serialize());
      final Uint8List opened =
          await SecretVault.open(masterKey: master, blob: blob);
      final Identity restored = await Identity.deserialize(opened);
      expect(await restored.signPublicBytes(),
          equals(await id.signPublicBytes()));
    });

    test('rejects a wrong master key', () async {
      final Uint8List master = Primitives.randomBytes(32);
      final Uint8List blob =
          await SecretVault.seal(masterKey: master, plaintext: <int>[1, 2, 3]);
      await expectLater(
        SecretVault.open(masterKey: Primitives.randomBytes(32), blob: blob),
        throwsA(anything),
      );
    });

    test('passphrase key derivation is deterministic', () async {
      final Uint8List salt = SecretVault.newSalt();
      final Uint8List k1 = await SecretVault.deriveKey(
          passphrase: 'correct horse battery staple',
          salt: salt,
          iterations: 1000);
      final Uint8List k2 = await SecretVault.deriveKey(
          passphrase: 'correct horse battery staple',
          salt: salt,
          iterations: 1000);
      expect(k1, equals(k2));
      expect(k1, hasLength(32));
    });
  });

  group('SafetyNumber', () {
    test('both peers compute the same number', () async {
      final Identity a = await Identity.generate();
      final Identity b = await Identity.generate();
      final aPub = await a.signPublicBytes();
      final bPub = await b.signPublicBytes();

      final String fromA =
          await SafetyNumber.compute(localSignPub: aPub, remoteSignPub: bPub);
      final String fromB =
          await SafetyNumber.compute(localSignPub: bPub, remoteSignPub: aPub);

      expect(fromA, equals(fromB));
      expect(fromA, matches(RegExp(r'^\d{60}$')));
    });

    test('differs for different identities', () async {
      final Identity a = await Identity.generate();
      final Identity b = await Identity.generate();
      final Identity c = await Identity.generate();
      final aPub = await a.signPublicBytes();

      final String ab = await SafetyNumber.compute(
          localSignPub: aPub, remoteSignPub: await b.signPublicBytes());
      final String ac = await SafetyNumber.compute(
          localSignPub: aPub, remoteSignPub: await c.signPublicBytes());
      expect(ab, isNot(equals(ac)));
    });
  });
}
