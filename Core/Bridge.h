#pragma once
#include <stddef.h>
#include <sys/types.h>
// Public libarchive ABI; macOS ships the library without SDK headers.
struct archive;
struct archive_entry;
#define ARCHIVE_OK 0
#define ARCHIVE_EOF 1
struct archive *archive_read_new(void);
int archive_read_free(struct archive *);
int archive_read_support_format_zip(struct archive *);
int archive_read_support_filter_all(struct archive *);
int archive_read_open_filename(struct archive *, const char *, size_t);
int archive_read_next_header(struct archive *, struct archive_entry **);
const char *archive_entry_pathname(struct archive_entry *);
ssize_t archive_read_data(struct archive *, void *, size_t);
int archive_read_data_skip(struct archive *);
