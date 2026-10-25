import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

Future<String> recognizeInvitation(String imagePath) async {
  final recognizer = TextRecognizer(script: TextRecognitionScript.japanese);
  try {
    final image = InputImage.fromFilePath(imagePath);
    return (await recognizer.processImage(image)).text;
  } finally {
    await recognizer.close();
  }
}

bool get invitationOcrSupported => true;
