VERSION := 0.1

ifdef PS4_PAYLOAD_SDK
    include $(PS4_PAYLOAD_SDK)/toolchain/orbis.mk
else
    $(error PS4_PAYLOAD_SDK is undefined)
endif

BUILDDIR := build
SRCDIR   := src

ELF_NORMAL    := db-rebuilder-v$(VERSION).elf
ELF_INSTALLER := db-rebuilder-v$(VERSION)-installer.elf
BIN_NORMAL    := db-rebuilder-v$(VERSION).bin

ELF_STRIP := $(firstword $(wildcard $(PS4_PAYLOAD_SDK)/bin/orbis-llvm-strip) \
	$(wildcard $(PS4_PAYLOAD_SDK)/bin/orbis-strip))

SRCS := $(SRCDIR)/main.c \
        $(SRCDIR)/util.c \
        $(SRCDIR)/sfo.c \
        $(SRCDIR)/memvfs.c \
        $(SRCDIR)/sqlite_db.c

SQLITE_SRC := $(SRCDIR)/sqlite3.c

OBJS := $(patsubst $(SRCDIR)/%.c,$(BUILDDIR)/%.o,$(SRCS))
SQLITE_OBJ := $(BUILDDIR)/sqlite3.o

PAYLOAD_ELF_C := $(BUILDDIR)/db_rebuilder_elf.c
BOOTSTRAP_OBJ := $(BUILDDIR)/bootstrap-bin.o
INSTALLER_BOOTSTRAP_OBJ := $(BUILDDIR)/bootstrap-installer.o
PUFF_OBJ := $(BUILDDIR)/puff.o

PYTHON ?= python3

COMMON_CFLAGS := -Os -std=c11 -DPLATFORM_PS4=1 -I$(SRCDIR) \
                 -ffunction-sections -fdata-sections \
                 -fno-asynchronous-unwind-tables \
                 -DPAYLOAD_VERSION=\"$(VERSION)\" \
                 -DSQLITE_THREADSAFE=0 -DSQLITE_OMIT_LOAD_EXTENSION \
                 -DSQLITE_OMIT_DEPRECATED \
                 -DSQLITE_OMIT_PROGRESS_CALLBACK \
                 -DSQLITE_OMIT_SHARED_CACHE \
                 -DSQLITE_OMIT_TCL_VARIABLE \
                 -DSQLITE_OMIT_AUTHORIZATION \
                 -DSQLITE_OMIT_COMPLETE \
                 -DSQLITE_OMIT_GET_TABLE \
                 -DSQLITE_OMIT_INCRBLOB \
                 -DSQLITE_OMIT_AUTOVACUUM \
                 -DSQLITE_OMIT_EXPLAIN \
                 -DSQLITE_OMIT_FOREIGN_KEY \
                 -DSQLITE_OMIT_LOOKASIDE \
                 -DSQLITE_OMIT_UTF16 \
                 -DSQLITE_OMIT_WAL \
                 -DSQLITE_OMIT_XFER_OPT \
                 -DSQLITE_OMIT_ALTERTABLE \
                 -DSQLITE_OMIT_ANALYZE \
                 -DSQLITE_OMIT_ATTACH \
                 -DSQLITE_OMIT_BETWEEN_OPTIMIZATION \
                 -DSQLITE_OMIT_BLOB_LITERAL \
                 -DSQLITE_OMIT_BUILTIN_TEST \
                 -DSQLITE_OMIT_CAST \
                 -DSQLITE_OMIT_CHECK \
                 -DSQLITE_OMIT_COMPILEOPTION_DIAGS \
                 -DSQLITE_OMIT_COMPOUND_SELECT \
                 -DSQLITE_OMIT_CTE \
                 -DSQLITE_OMIT_DATETIME_FUNCS \
                 -DSQLITE_OMIT_DECLTYPE \
                 -DSQLITE_OMIT_DESERIALIZE \
                 -DSQLITE_OMIT_FLAG_PRAGMAS \
                 -DSQLITE_OMIT_GENERATED_COLUMNS \
                 -DSQLITE_OMIT_HEX_INTEGER \
                 -DSQLITE_OMIT_INTEGRITY_CHECK \
                 -DSQLITE_OMIT_LIKE_OPTIMIZATION \
                 -DSQLITE_OMIT_LOCALTIME \
                 -DSQLITE_OMIT_OR_OPTIMIZATION \
                 -DSQLITE_OMIT_QUICKBALANCE \
                 -DSQLITE_OMIT_REINDEX \
                 -DSQLITE_OMIT_SCHEMA_PRAGMAS \
                 -DSQLITE_OMIT_SCHEMA_VERSION_PRAGMAS \
                 -DSQLITE_OMIT_SUBQUERY \
                 -DSQLITE_OMIT_TEMPDB \
                 -DSQLITE_OMIT_TRACE \
                 -DSQLITE_OMIT_TRIGGER \
                 -DSQLITE_OMIT_VACUUM \
                 -DSQLITE_OMIT_VIEW \
                 -DSQLITE_OMIT_VIRTUALTABLE \
                 -DSQLITE_OMIT_WINDOWFUNC \
                 -DSQLITE_OMIT_AUTOINIT \
                 -DSQLITE_DEFAULT_MEMSTATUS=0

CFLAGS := -Wall -Wextra -Werror $(COMMON_CFLAGS)

SQLITE_CFLAGS := -w $(COMMON_CFLAGS) -Oz

LDLIBS := -lc -lkernel

LDFLAGS := -Wl,--gc-sections

.PHONY: all clean test

all: $(ELF_NORMAL) $(ELF_INSTALLER) $(BIN_NORMAL)

$(BUILDDIR):
	mkdir -p $(BUILDDIR)

$(BUILDDIR)/%.o: $(SRCDIR)/%.c | $(BUILDDIR)
	$(CC) $(CFLAGS) -c -o $@ $<

$(BUILDDIR)/memvfs.o: $(SRCDIR)/memvfs.c | $(BUILDDIR)
	$(CC) $(CFLAGS) -Wno-unused-parameter -c -o $@ $<

$(SQLITE_OBJ): $(SQLITE_SRC) | $(BUILDDIR)
	$(CC) $(SQLITE_CFLAGS) -c -o $@ $<

$(PUFF_OBJ): $(SRCDIR)/puff.c | $(BUILDDIR)
	$(CC) $(CFLAGS) -fno-builtin -c -o $@ $<

$(ELF_NORMAL): $(OBJS) $(SQLITE_OBJ)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^ $(LDLIBS)
	$(ELF_STRIP) --strip-all $@
	$(ELF_STRIP) --remove-section=.eh_frame --remove-section=.eh_frame_hdr --remove-section=.comment $@

$(PAYLOAD_ELF_C): $(ELF_NORMAL) tools/deflate.py | $(BUILDDIR)
	$(PYTHON) tools/deflate.py $(ELF_NORMAL) $@

$(BOOTSTRAP_OBJ): $(SRCDIR)/bootstrap-bin.c $(PAYLOAD_ELF_C) | $(BUILDDIR)
	$(CC) $(CFLAGS) -I$(BUILDDIR) -c -o $@ $<

$(INSTALLER_BOOTSTRAP_OBJ): $(SRCDIR)/bootstrap-bin.c $(PAYLOAD_ELF_C) | $(BUILDDIR)
	$(CC) $(CFLAGS) -DBUILD_INSTALLER -I$(BUILDDIR) -c -o $@ $<

$(BIN_NORMAL): $(BOOTSTRAP_OBJ) $(PUFF_OBJ) $(SRCDIR)/bin_x86_64.x | $(BUILDDIR)
	$(LD) -T $(SRCDIR)/bin_x86_64.x -o $(BUILDDIR)/bootstrap-bin.elf $(BOOTSTRAP_OBJ) $(PUFF_OBJ)
	$(OBJCOPY) -O binary --only-section=.text $(BUILDDIR)/bootstrap-bin.elf $@

$(ELF_INSTALLER): $(INSTALLER_BOOTSTRAP_OBJ) $(PUFF_OBJ) | $(BUILDDIR)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^ $(LDLIBS)
	$(ELF_STRIP) --strip-all $@
	$(ELF_STRIP) --remove-section=.eh_frame --remove-section=.eh_frame_hdr --remove-section=.comment $@

clean:
	rm -rf $(BUILDDIR) $(ELF_NORMAL) $(ELF_INSTALLER) $(BIN_NORMAL)
