#define _DARWIN_C_SOURCE 1
#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#ifndef O_CLOEXEC
#define O_CLOEXEC 0
#endif

static const char backend[] = "herdr\n";
static const char crew_harness[] = "pi\n";
static const char startup_memory_budget[] = "7500\n";
static const char crew_dispatch[] =
    "{\n"
    "  \"rules\": [\n"
    "    {\n"
    "      \"when\": \"planning, architecture, diagnosis, design, security, or a bounded review of a plan or output\",\n"
    "      \"use\": {\n"
    "        \"harness\": \"pi\",\n"
    "        \"model\": \"gpt-6-astra\",\n"
    "        \"effort\": \"high\"\n"
    "      },\n"
    "      \"why\": \"Astra plans: scarce and strategic, at most one or two bounded high-reasoning passes on a ship.\"\n"
    "    },\n"
    "    {\n"
    "      \"when\": \"mechanical, fully specified edits\",\n"
    "      \"use\": {\n"
    "        \"harness\": \"pi\",\n"
    "        \"model\": \"xai/grok-4.6\",\n"
    "        \"effort\": \"medium\"\n"
    "      },\n"
    "      \"why\": \"Grok executes mechanical, fully specified edits so scarce Astra is reserved for at most one or two bounded high-reasoning passes.\"\n"
    "    },\n"
    "    {\n"
    "      \"when\": \"well-scoped implementation\",\n"
    "      \"use\": {\n"
    "        \"harness\": \"pi\",\n"
    "        \"model\": \"xai/grok-4.6\",\n"
    "        \"effort\": \"high\"\n"
    "      },\n"
    "      \"why\": \"Grok executes well-scoped implementation; Astra remains scarce and is not the default implementation model.\"\n"
    "    },\n"
    "    {\n"
    "      \"when\": \"driving no-mistakes, validation, CI, or any long unattended pipeline\",\n"
    "      \"use\": {\n"
    "        \"harness\": \"pi\",\n"
    "        \"model\": \"xai/grok-4.6\",\n"
    "        \"effort\": \"high\"\n"
    "      },\n"
    "      \"why\": \"Never overnight Astra: unattended no-mistakes must run on Grok after any Astra pass, never as an automatic Astra cadence.\"\n"
    "    }\n"
    "  ],\n"
    "  \"default\": {\n"
    "    \"harness\": \"pi\",\n"
    "    \"model\": \"xai/grok-4.6\",\n"
    "    \"effort\": \"high\"\n"
    "  }\n"
    "}\n";

struct target {
  const char *name;
  const char *content;
  size_t length;
  bool budget;
};

static const struct target targets[] = {
    {"startup-memory-budget", startup_memory_budget,
     sizeof(startup_memory_budget) - 1, true},
    {"backend", backend, sizeof(backend) - 1, false},
    {"crew-harness", crew_harness, sizeof(crew_harness) - 1, false},
    {"crew-dispatch.json", crew_dispatch, sizeof(crew_dispatch) - 1, false},
};

static const char *home_path;
static int home_fd = -1;
static int config_fd = -1;

static void fail_path(const char *message, const char *name) {
  if (name == NULL) {
    fprintf(stderr, "firstmate-config: %s: %s\n", message, home_path);
  } else {
    fprintf(stderr, "firstmate-config: %s: %s/config/%s\n", message,
            home_path, name);
  }
}

static bool same_identity(const struct stat *left, const struct stat *right) {
  return left->st_dev == right->st_dev && left->st_ino == right->st_ino;
}

static bool same_metadata(const struct stat *left, const struct stat *right) {
#ifdef __APPLE__
  return same_identity(left, right) && left->st_size == right->st_size &&
         left->st_ctimespec.tv_sec == right->st_ctimespec.tv_sec &&
         left->st_ctimespec.tv_nsec == right->st_ctimespec.tv_nsec &&
         left->st_mtimespec.tv_sec == right->st_mtimespec.tv_sec &&
         left->st_mtimespec.tv_nsec == right->st_mtimespec.tv_nsec;
#else
  return same_identity(left, right) && left->st_size == right->st_size &&
         left->st_ctim.tv_sec == right->st_ctim.tv_sec &&
         left->st_ctim.tv_nsec == right->st_ctim.tv_nsec &&
         left->st_mtim.tv_sec == right->st_mtim.tv_sec &&
         left->st_mtim.tv_nsec == right->st_mtim.tv_nsec;
#endif
}

static int open_directory_at(int parent, const char *name, bool create) {
  int fd = openat(parent, name,
                  O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
  if (fd >= 0 || !create || errno != ENOENT) {
    return fd;
  }
  if (mkdirat(parent, name, 0700) < 0 && errno != EEXIST) {
    return -1;
  }
  return openat(parent, name,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
}

static int open_directory_chain(const char *path, bool create) {
  if (path == NULL || path[0] != '/' || path[1] == '\0') {
    errno = EINVAL;
    return -1;
  }
  char *copy = strdup(path + 1);
  if (copy == NULL) {
    return -1;
  }
  int fd = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC);
  if (fd < 0) {
    free(copy);
    return -1;
  }
  char *save = NULL;
  for (char *part = strtok_r(copy, "/", &save); part != NULL;
       part = strtok_r(NULL, "/", &save)) {
    if (strcmp(part, ".") == 0 || strcmp(part, "..") == 0) {
      close(fd);
      free(copy);
      errno = EINVAL;
      return -1;
    }
    int next = open_directory_at(fd, part, create);
    close(fd);
    if (next < 0) {
      free(copy);
      return -1;
    }
    fd = next;
  }
  free(copy);
  return fd;
}

static bool verify_directories(void) {
  struct stat held_home;
  struct stat held_config;
  struct stat current_home;
  struct stat current_config;
  int current_home_fd = open_directory_chain(home_path, false);
  if (current_home_fd < 0 || fstat(home_fd, &held_home) < 0 ||
      fstat(config_fd, &held_config) < 0 ||
      fstat(current_home_fd, &current_home) < 0) {
    if (current_home_fd >= 0) {
      close(current_home_fd);
    }
    return false;
  }
  int current_config_fd = open_directory_at(current_home_fd, "config", false);
  bool valid = current_config_fd >= 0 &&
               fstat(current_config_fd, &current_config) == 0 &&
               same_identity(&held_home, &current_home) &&
               same_identity(&held_config, &current_config);
  if (current_config_fd >= 0) {
    close(current_config_fd);
  }
  close(current_home_fd);
  return valid;
}

static unsigned char *read_all(int fd, size_t *length) {
  size_t capacity = 128;
  size_t used = 0;
  unsigned char *data = malloc(capacity);
  if (data == NULL) {
    return NULL;
  }
  for (;;) {
    if (used == capacity) {
      if (capacity > SIZE_MAX / 2) {
        free(data);
        errno = EOVERFLOW;
        return NULL;
      }
      capacity *= 2;
      unsigned char *expanded = realloc(data, capacity);
      if (expanded == NULL) {
        free(data);
        return NULL;
      }
      data = expanded;
    }
    ssize_t count = read(fd, data + used, capacity - used);
    if (count < 0) {
      if (errno == EINTR) {
        continue;
      }
      free(data);
      return NULL;
    }
    if (count == 0) {
      *length = used;
      return data;
    }
    used += (size_t)count;
  }
}

static bool valid_budget(const unsigned char *data, size_t length) {
  if (length < 2 || data[0] < '1' || data[0] > '9' ||
      data[length - 1] != '\n') {
    return false;
  }
  for (size_t index = 1; index + 1 < length; ++index) {
    if (data[index] < '0' || data[index] > '9') {
      return false;
    }
  }
  return true;
}

#ifdef FIRSTMATE_CONFIG_TESTING
static void test_hook(const char *name) {
  const char *selected = getenv("FIRSTMATE_CONFIG_TEST_HOOK");
  if (selected != NULL && strcmp(selected, name) == 0) {
    raise(SIGSTOP);
  }
}
#else
static void test_hook(const char *name) { (void)name; }
#endif

static int preserve_target(const struct target *target) {
  int fd = openat(config_fd, target->name,
                  O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
  if (fd < 0) {
    fail_path("could not open existing regular target", target->name);
    return 1;
  }
  struct stat before;
  struct stat after;
  struct stat current;
  size_t length = 0;
  if (fstat(fd, &before) < 0 || !S_ISREG(before.st_mode) ||
      before.st_nlink < 1 || (target->budget && before.st_nlink != 1)) {
    close(fd);
    fail_path("invalid existing regular target", target->name);
    return 1;
  }
  unsigned char *data = read_all(fd, &length);
  if (data == NULL || fstat(fd, &after) < 0) {
    free(data);
    close(fd);
    fail_path("could not read existing regular target", target->name);
    return 1;
  }
  test_hook("before-preserve-boundary");
  bool current_valid =
      fstatat(config_fd, target->name, &current, AT_SYMLINK_NOFOLLOW) == 0 &&
      S_ISREG(current.st_mode) && current.st_nlink == after.st_nlink &&
      after.st_nlink == before.st_nlink &&
      same_metadata(&before, &after) && same_metadata(&after, &current) &&
      verify_directories();
  bool content_valid =
      !target->budget || valid_budget(data, length);
  bool unchanged = length == target->length &&
                   memcmp(data, target->content, target->length) == 0;
  free(data);
  close(fd);
  if (!current_valid || !content_valid) {
    fail_path(target->budget ? "invalid captain-selected startup memory budget"
                             : "target changed during preservation",
              target->name);
    return 1;
  }
  printf("firstmate-config: %s %s/config/%s\n",
         target->budget ? "preserved captain-selected"
                        : (unchanged ? "unchanged"
                                     : "preserved locally changed"),
         home_path, target->name);
  return 0;
}

static bool write_all(int fd, const char *data, size_t length) {
  size_t offset = 0;
  while (offset < length) {
    ssize_t count = write(fd, data + offset, length - offset);
    if (count < 0) {
      if (errno == EINTR) {
        continue;
      }
      return false;
    }
    if (count == 0) {
      errno = EIO;
      return false;
    }
    offset += (size_t)count;
  }
  return true;
}

static int publish_target(const struct target *target) {
  static unsigned int counter;
  char temporary[96];
  int temporary_fd = -1;
  for (unsigned int attempt = 0; attempt < 100 && temporary_fd < 0; ++attempt) {
    snprintf(temporary, sizeof(temporary), ".firstmate-config.%ld.%u",
             (long)getpid(), counter++);
    temporary_fd = openat(config_fd, temporary,
                          O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
                          0600);
    if (temporary_fd < 0 && errno != EEXIST) {
      break;
    }
  }
  if (temporary_fd < 0 || !write_all(temporary_fd, target->content,
                                      target->length) ||
      fsync(temporary_fd) < 0) {
    if (temporary_fd >= 0) {
      close(temporary_fd);
      unlinkat(config_fd, temporary, 0);
    }
    fail_path("could not write temporary file", target->name);
    return 1;
  }
  struct stat temporary_state;
  if (fstat(temporary_fd, &temporary_state) < 0 ||
      !S_ISREG(temporary_state.st_mode) || temporary_state.st_nlink != 1 ||
      temporary_state.st_size != (off_t)target->length) {
    close(temporary_fd);
    unlinkat(config_fd, temporary, 0);
    fail_path("could not finalize temporary file", target->name);
    return 1;
  }
  test_hook("before-publish");
  if (linkat(config_fd, temporary, config_fd, target->name, 0) < 0) {
    int link_error = errno;
    close(temporary_fd);
    unlinkat(config_fd, temporary, 0);
    fail_path(link_error == EEXIST
                  ? "target appeared during publication and was preserved"
                  : "could not publish target",
              target->name);
    return 1;
  }
  if (unlinkat(config_fd, temporary, 0) < 0) {
    close(temporary_fd);
    fail_path("could not remove publication link", target->name);
    return 1;
  }
  struct stat published_state;
  if (fstat(temporary_fd, &published_state) < 0 ||
      !S_ISREG(published_state.st_mode) || published_state.st_nlink != 1) {
    close(temporary_fd);
    fail_path("could not validate published target", target->name);
    return 1;
  }
  test_hook("before-publish-boundary");
  struct stat before_read;
  struct stat after_read;
  struct stat current;
  size_t length = 0;
  unsigned char *data = NULL;
  bool readable = fstat(temporary_fd, &before_read) == 0 &&
                  lseek(temporary_fd, 0, SEEK_SET) == 0;
  if (readable) {
    data = read_all(temporary_fd, &length);
    readable = data != NULL && fstat(temporary_fd, &after_read) == 0;
  }
  bool valid =
      readable && S_ISREG(before_read.st_mode) &&
      S_ISREG(after_read.st_mode) && before_read.st_nlink == 1 &&
      after_read.st_nlink == 1 &&
      fstatat(config_fd, target->name, &current, AT_SYMLINK_NOFOLLOW) == 0 &&
      S_ISREG(current.st_mode) && current.st_nlink == 1 &&
      same_metadata(&published_state, &before_read) &&
      same_metadata(&before_read, &after_read) &&
      same_metadata(&after_read, &current) && length == target->length &&
      memcmp(data, target->content, target->length) == 0 &&
      verify_directories();
  free(data);
  if (close(temporary_fd) < 0) {
    valid = false;
  }
  if (!valid) {
    fail_path("target changed during publication", target->name);
    return 1;
  }
  printf("firstmate-config: created %s/config/%s\n", home_path, target->name);
  return 0;
}

static int materialize_target(const struct target *target) {
  if (!verify_directories()) {
    fail_path("canonical directory changed during activation", NULL);
    return 1;
  }
  struct stat current;
  if (fstatat(config_fd, target->name, &current, AT_SYMLINK_NOFOLLOW) == 0) {
    if (!S_ISREG(current.st_mode)) {
      fail_path("refusing symlink or non-regular target", target->name);
      return 1;
    }
    return preserve_target(target);
  }
  if (errno != ENOENT) {
    fail_path("could not inspect target", target->name);
    return 1;
  }
  return publish_target(target);
}

int main(int argc, char **argv) {
  if (argc != 2) {
    fprintf(stderr, "usage: %s <canonical-firstmate-home>\n", argv[0]);
    return 2;
  }
  home_path = argv[1];
  home_fd = open_directory_chain(home_path, true);
  if (home_fd < 0) {
    fail_path("canonical home is not a stable regular directory", NULL);
    return 1;
  }
  config_fd = open_directory_at(home_fd, "config", true);
  if (config_fd < 0) {
    fail_path("config path is not a stable regular directory", NULL);
    close(home_fd);
    return 1;
  }
  test_hook("after-config-open");
  int result = 0;
  for (size_t index = 0; index < sizeof(targets) / sizeof(targets[0]); ++index) {
    struct stat current;
    int inspected = fstatat(config_fd, targets[index].name, &current,
                            AT_SYMLINK_NOFOLLOW);
    if (inspected == 0 && !S_ISREG(current.st_mode)) {
      fail_path("refusing symlink or non-regular target", targets[index].name);
      result = 1;
      break;
    }
    if (inspected < 0 && errno != ENOENT) {
      fail_path("could not inspect target", targets[index].name);
      result = 1;
      break;
    }
  }
  for (size_t index = 0;
       result == 0 && index < sizeof(targets) / sizeof(targets[0]); ++index) {
    result = materialize_target(&targets[index]);
  }
  close(config_fd);
  close(home_fd);
  return result;
}
