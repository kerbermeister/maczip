# Third-party software

MacZip uses the unmodified, standalone 7-Zip 26.05 console program by Igor Pavlov,
copyright © 1999–2026 Igor Pavlov, as a separate helper executable.

7-Zip is licensed under the GNU LGPL, with some components under the BSD 3-clause
license and some under the unRAR license restriction. The full license text,
including LGPL terms and the unRAR restriction, is distributed in
`Vendor/7zip/License.txt` and `Vendor/7zip/MANUAL/general/license.htm` and copied
into `MacZip.app/Contents/Resources/7zip/` by the build script.

Official project, license information and corresponding source code:
- https://www.7-zip.org/
- https://www.7-zip.org/license.txt
- https://github.com/ip7z/7zip/releases/tag/26.05
- https://github.com/ip7z/7zip/releases/download/26.05/7z2605-src.tar.xz

MacZip does not modify or link against the 7-Zip executable. You may replace
`MacZip.app/Contents/Helpers/7zz` with a compatible version. For source builds,
set `MACZIP_7ZZ` to an executable path. Changing a signed application requires
signing the modified bundle again.

RAR creation is not provided. The unRAR restriction prohibits use of the unRAR
code to develop a RAR-compatible archiver. See the bundled license for details.
