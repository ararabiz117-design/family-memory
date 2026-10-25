import 'invitation_ocr_stub.dart'
    if (dart.library.io) 'invitation_ocr_mobile.dart'
    as platform;

Future<String> recognizeInvitation(String imagePath) =>
    platform.recognizeInvitation(imagePath);

bool get invitationOcrSupported => platform.invitationOcrSupported;
