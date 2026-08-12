# MakerNote fixtures

These reduced JPEG files retain real camera EXIF and MakerNote payloads while keeping the test bundle small:

- `Fujifilm_FinePix_E500.jpg`
- `Nikon_D70.jpg`
- `Sony_HDR-HC3.jpg`

The reduced RAW fixtures exercise ImageIO and the vendor MakerNote parsers without bundling full-resolution image data:

- `Fujifilm_FinePix_S5Pro.raf` — verifies that a reduced RAF unsupported by ImageIO fails safely
- `Nikon_D70.nef` — expected make/model `NIKON CORPORATION` / `NIKON D70`
- `Sony_ILCE-1M2.arw` — expected make/model `SONY` / `ILCE-1M2`; reduced from a 2025 Alpha 1 II lossy-compressed sample

They come from the archived [`ianare/exif-samples`](https://github.com/ianare/exif-samples) test corpus and are used under the [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/) license. The files are redistributed unchanged; attribution belongs to that repository and its contributors.

The RAW fixtures come from the official [`exiftool/exiftool`](https://github.com/exiftool/exiftool) test suite. Their expected values are pinned from ExifTool 13.59 output. ExifTool is distributed under the same terms as Perl (Artistic License or GNU GPL).

The Sony Alpha 1 II fixture is the first 512 KiB of the CC0 sample published by
[`raw.pixls.us`](https://raw.pixls.us/getfile.php/7835/nice/Sony%20-%20ILCE-1M2%20-%2014bit%20Lossy%20%283%3A2%29.ARW).
The pixel payload is intentionally omitted; its TIFF/EXIF directories remain intact so ImageIO and the Sony metadata projection can be regression-tested without adding the full 21.7 MiB RAW to the test bundle.
