import 'dart:convert';
import 'dart:typed_data';

import 'package:dtorrent_task_v2/src/standalone/dtorrent_common.dart';
import 'package:b_encode_decode/b_encode_decode.dart' as bencode;
import 'package:logging/logging.dart';

import 'scrape_event.dart';
import 'http_tracker_base.dart';
import 'scrape.dart';

var _log = Logger('HttpScrape');

///
/// Torrent http scrape.
///
/// extends from Scrape class
class HttpScrape extends Scrape with HttpTrackerBase {
  HttpScrape(Uri scrapeUrl, [int maxRetryTime = 3])
      : super('${scrapeUrl.origin}${scrapeUrl.path}', scrapeUrl, maxRetryTime);

  @override
  Map<String, dynamic>? generateQueryParameters(Map<String, dynamic> options) {
    if (infoHashSet.isEmpty) return null;
    var infos = [];
    // infohash value usually can not be decode by utf8, because some special character,
    // so I transform them with String.fromCharCodes , when transform them to the query component, use latin1 encoding
    for (var infoHash in infoHashSet) {
      var query = Uri.encodeQueryComponent(String.fromCharCodes(infoHash),
          encoding: latin1);
      infos.add(query);
    }
    return {'info_hash': infos};
  }

  @override
  ScrapeEvent processResponseData(Uint8List data) {
    var result = bencode.decode(data) as Map;
    if (result['failure reason'] != null) {
      throw Exception(String.fromCharCodes(result['failure reason']));
    }
    var event = ScrapeEvent(url);
    // Convert the key value of the file to Hex.
    // var files = <String, Map>{};
    result.forEach((key, value) {
      if (key == 'files') {
        var list = value;
        for (var key in list.keys) {
          var fileHash = transformBufferToHexString((key as String).codeUnits);
          var fileInfo = list[key] as Map;
          var file = ScrapeResult(fileHash);
          fileInfo.forEach((key, value) {
            if (key == 'complete') {
              file.complete = value;
              return;
            }
            if (key == 'incomplete') {
              file.incomplete = value;
              return;
            }
            if (key == 'downloaded') {
              file.downloaded = value;
              return;
            }
            if (key == 'name') {
              file.name = value;
              return;
            }
            file.setInfo(key, value);
          });
          event.addFile(fileHash, file);
        }
      } else {
        event.setInfo(key, value);
      }
    });
    return event;
  }

  @override
  Future<ScrapeEvent?> scrape(Map<String, dynamic> options) async {
    // Currently, scrape does not require providing access parameters.
    try {
      return await httpGet<ScrapeEvent>(options);
    } catch (e) {
      _log.warning('Scrape Error : $url', e);
      return null;
    } finally {
      await close();
    }
  }

  @override
  Uri get url => scrapeUrl;
}
