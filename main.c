#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <sched.h>
#include <sys/mount.h>
#include <sys/wait.h>
#include <assert.h>

typedef int (*func_ptr)(void*);
char *SHELL[] = {(char *)"/bin/bash", NULL};
char* stack;

#define STACK_SIZE 65536
#define ROOT_DIR "/home/sln/repos/ccontainer/rootfs"
#define NETNS "/var/run/netns/ccontainer"

// Environmental variables
#define CONTAINER_NAME "notadocker"
#define PATH "/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin"
//#define TERM "rxvt-16color"
#define TERM "konsole-16color"

void set_env() {
    clearenv();
    setenv("TERM", TERM, 0);
    setenv("PATH", PATH, 0);
    sethostname(CONTAINER_NAME, sizeof(CONTAINER_NAME));
}

void set_net_ns() {
    int fd_ns = open(NETNS, O_RDONLY);
    if (fd_ns == -1) {
        perror("open fd_ns");
        exit(EXIT_FAILURE);
    }
    if (setns(fd_ns, CLONE_NEWNET) == -1) {
        perror("setns");
        close(fd_ns);
        exit(EXIT_FAILURE);
    }
    close(fd_ns);
}


void do_chroot() {
    chroot(ROOT_DIR);
    chdir("/");
}

int do_clone(func_ptr foo, int flags) {
    stack = (char*)malloc(STACK_SIZE);
    assert(stack);

    int  pid = clone(foo, stack + STACK_SIZE, flags, 0);
    if (pid < 0) {
        perror("clone child");
    }
    return pid;
}

void do_mounts() {
    if (mount("proc", "/proc", "proc", 0, 0) == -1) {
        perror("mount proc");
        exit(EXIT_FAILURE);
    }
    if (mount("sys", "/sys", "sysfs", MS_BIND | MS_REC, NULL) == -1) {
		perror("mount sys");
        exit(EXIT_FAILURE);
	}
}

void do_unmounts() {
    umount("/proc");
    umount("/sys");
}

void container_init() {
    set_env();
    set_net_ns();
    do_chroot();
    do_mounts();
}

void container_delete() {
    do_unmounts();
}

void container_run_shell() {
    switch (fork()) {
    case -1:
        perror("fork");
    case 0:
        execvp(SHELL[0], SHELL);
    default:
        wait(0);
    }
}

int container_start(void *arg) {
    container_init();
    container_run_shell();
    container_delete();
    return EXIT_SUCCESS;
}

int container_run() {
    int cont_pid = do_clone(container_start, CLONE_NEWPID | CLONE_NEWUTS | SIGCHLD | CLONE_NEWNET | CLONE_NEWNS);
    wait(0);
    free(stack);
    return EXIT_SUCCESS;
}

int main() {
    return container_run();
}
