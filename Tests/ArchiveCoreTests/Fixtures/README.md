# RAR test fixtures

The RAR 4 and RAR 5 fixtures come from the libarchive project's regression suite:

- https://github.com/libarchive/libarchive/blob/master/libarchive/test/test_read_format_rar.rar.uu
- https://github.com/libarchive/libarchive/blob/master/libarchive/test/test_read_format_rar5_stored.rar.uu
- https://github.com/libarchive/libarchive/blob/master/libarchive/test/test_read_format_rar4_encrypted.rar.uu
- https://github.com/libarchive/libarchive/blob/master/libarchive/test/test_read_format_rar4_encrypted_filenames.rar.uu
- https://github.com/libarchive/libarchive/blob/master/libarchive/test/test_read_format_rar5_encrypted.rar.uu
- https://github.com/libarchive/libarchive/blob/master/libarchive/test/test_read_format_rar5_encrypted_filenames.rar.uu

The original uuencoded fixtures are retained alongside their decoded .rar files.
See LIBARCHIVE-LICENSE for upstream license terms. These are test data only and
are not included in the MacZip application bundle.

`sample.iso` is a generated ISO/Joliet image containing a single `hello.txt` file
with the contents `MacZip ISO fixture\n`. It was generated with macOS hdiutil
for the MacZip tests and contains no third-party data.
