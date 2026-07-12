import '../core/model/paper_constants.dart';

class PaperWindowArguments {
  const PaperWindowArguments({required this.paperId});

  static const marker = '--repapertodo-paper-window';

  final String paperId;

  static PaperWindowArguments? tryParse(List<String> arguments) {
    if (arguments.length != 2 || arguments.first != marker) {
      return null;
    }
    final paperId = normalizeLocalModelId(arguments[1]);
    if (paperId.isEmpty || paperId != arguments[1]) {
      return null;
    }
    return PaperWindowArguments(paperId: paperId);
  }
}
