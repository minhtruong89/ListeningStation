abstract class IQRService {
  String? decodeQrCode(String rawData);
}

class QRService implements IQRService {
  @override
  String? decodeQrCode(String rawData) {
    if (rawData.isEmpty) return null;
    // Mobile scanner returns raw scanned data directly.
    return rawData;
  }
}
