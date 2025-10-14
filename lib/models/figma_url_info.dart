enum FigmaFileType {
  design,
  figjam,
  slides,
}

class FigmaUrlInfo {
  final String fileKey;
  final FigmaFileType fileType;
  final String? branchId;

  FigmaUrlInfo({
    required this.fileKey,
    required this.fileType,
    this.branchId,
  });
}
