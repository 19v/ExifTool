# MakerNote fixtures

`Apple_iPhone7.jpg` is ExifTool's reduced `t/images/Apple.jpg` regression fixture. It is used to pin the Apple MakerNote projection against `t/Apple_2.out`.

These reduced JPEG files retain real camera EXIF and MakerNote payloads while keeping the test bundle small:

- `Fujifilm_FinePix_E500.jpg`
- `Nikon_D70.jpg`
- `Sony_HDR-HC3.jpg`

The reduced RAW fixtures exercise ImageIO and the vendor MakerNote parsers without bundling full-resolution image data:

- `Fujifilm_FinePix_S5Pro.raf` — verifies that a reduced RAF unsupported by ImageIO fails safely
- `Nikon_D70.nef` — expected make/model `NIKON CORPORATION` / `NIKON D70`
- `Nikon_Z8.nef` — first 256 KiB of a Nikon Z8 high-efficiency sample; expected make/model `NIKON CORPORATION` / `NIKON Z 8`
- `Fujifilm_X-T5.raf` — first 4 MiB of a lossless-compressed Fujifilm X-T5 sample; expected make/model `FUJIFILM` / `X-T5`
- `Sony_ILCE-1M2.arw` — expected make/model `SONY` / `ILCE-1M2`; reduced from a 2025 Alpha 1 II lossy-compressed sample

They come from the archived [`ianare/exif-samples`](https://github.com/ianare/exif-samples) test corpus and are used under the [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/) license. The files are redistributed unchanged; attribution belongs to that repository and its contributors.

The RAW fixtures come from the official [`exiftool/exiftool`](https://github.com/exiftool/exiftool) test suite. Their expected values are pinned from ExifTool 13.59 output. ExifTool is distributed under the same terms as Perl (Artistic License or GNU GPL).

The Sony Alpha 1 II fixture is the first 512 KiB of the CC0 sample published by
[`raw.pixls.us`](https://raw.pixls.us/getfile.php/7835/nice/Sony%20-%20ILCE-1M2%20-%2014bit%20Lossy%20%283%3A2%29.ARW).
The pixel payload is intentionally omitted; its TIFF/EXIF directories remain intact so ImageIO and the Sony metadata projection can be regression-tested without adding the full 21.7 MiB RAW to the test bundle.

The modern Nikon and Fujifilm fixtures are also reduced from CC0 samples published by raw.pixls.us:

- [`Nikon Z8 high efficiency`](https://raw.pixls.us/getfile.php/6616/nice/Nikon%20-%20Z%208%20-%208bit%208bit%20compressed%20%283%3A2%29.NEF), original SHA-256 `82df041542b8d328738443bb5ff3373b396e406ecc8cbe7dc3b35252790c53e7`
- [`Fujifilm X-T5 lossless compressed`](https://raw.pixls.us/getfile.php/6123/nice/Fujifilm%20-%20X-T5%20-%2014bit%2014bit%20compressed%20%283%3A2%29.RAF), original SHA-256 `cddd7ae0c43f9280876e5fdcbdf8878718972ebd3d034d8affc8cfc6752d33dc`

The checked-in reduced files have SHA-256 values `51b7953e8b263c4b92be90318079ec1be111b4af6a23f0719310311150fbaeb6` and `7740a5666cff3127f81397b15e0ee507ff7e6161dd8576d7cfbb4eabe22882b0`, respectively.
