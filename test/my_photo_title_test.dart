import 'package:carden/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('My Puzzles titles read as dates: new uploads and the old "My photo d/m" rows', () {
    expect(newMyPhotoTitle(DateTime(2026, 10, 12)), 'Photo, 12 Oct');
    expect(myPhotoTitle('My photo 12/10'), 'Photo, 12 Oct');
    expect(MyPuzzle.fromRow('m', {'fileId': 'f', 'title': 'My photo 3/1'}).title, 'Photo, 3 Jan');
    expect(myPhotoTitle('My photo 40/13'), 'My photo 40/13', reason: 'not a date: kept');
    expect(myPhotoTitle('Grandma at the lake'), 'Grandma at the lake');
  });
}
