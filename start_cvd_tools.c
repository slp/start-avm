#include <errno.h>
#include <stdio.h>
#include <fcntl.h>
#include <stdlib.h>
#include <unistd.h>
#include <libgen.h>
#include <assert.h>
#include <unistd.h>
#include <string.h>
#include <sys/un.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <sys/socket.h>
#include <linux/vm_sockets.h>
#include <netinet/in.h>

#define SOCK_BUF_SIZE 4096
#define BUFFER_SIZE 1024
#define INSTANCE_DIR "/qemu/"

const char CONFIG_SERVER_DATA[] = "\x0a\x35\x0a\x0c\x31\x39\x32\x2e\x31\x36\x38\x2e\x39\x37\x2e\x32\x12\x0c\x31\x39\x32\x2e\x31\x36\x38\x2e\x39\x37\x2e\x31\x1a\x07\x38\x2e\x38\x2e\x38\x2e\x38\x22\x0c\x31\x39\x32\x2e\x31\x36\x38\x2e\x39\x37\x2e\x33\x28\x1e\x12\x0b\x08\xd0\x05\x10\x80\x0a\x18\xc0\x02\x20\x3c";

static char *buf;
static char *scratch;

struct environment {
	char *base_dir;
	char **envp;

	int vsock_user;
	int real_config_server;

	int km_in;
	int km_out;
	int gk_in;
	int gk_out;
	int kn_in;
	int lc_in;
	int bt_in;
	int bt_out;

	int adb_sock;
	int cu_sock;
	int ms_vsock;
	int cs_vsock;

	int adb_pipe[2];
	int kevs_pipe[2];
};

int init_unix_socket(struct environment *env, char *path)
{
	struct sockaddr_un local;
	int len;
	int ret;
	int fd;

	fd = socket(AF_UNIX, SOCK_STREAM, 0);
	if(fd == -1) {
		perror("Error creating unix socket");
		exit(1);
	}

	local.sun_family = AF_UNIX;
	strcpy(local.sun_path, path);
	unlink(local.sun_path);
	len = strlen(local.sun_path) + sizeof(local.sun_family);

	ret = bind(fd, (struct sockaddr *)&local, len);
	if (ret == -1) {
		perror("Error binding unix socket");
		exit(1);
	}

	ret = listen(fd, 5);
	if (ret == -1) {
		perror("Error listening in unix socket");
		exit(1);
	}

	return fd;
}

int init_inet_socket(struct environment *env)
{
	struct sockaddr_in inet;
	int ret;
	int fd;

	fd = socket(AF_INET, SOCK_STREAM, 0);
	if (fd == -1)
	{
		perror("Error creating server socket");
		exit(1);
	}

	ret = setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &(int){1}, sizeof(int));
	if (ret < 0) {
		perror("Error in setsockopt(SO_REUSEADDR)");
		exit(1);
	}

	memset(&inet, 0, sizeof(struct sockaddr_in));
	inet.sin_family = AF_INET;
	inet.sin_port = htons(6520);

	ret = bind(fd, (struct sockaddr *)&inet, sizeof(struct sockaddr_in));
	if (ret == -1)
	{
		perror("Error binding inet socket");
		exit(1);
	}

	ret = listen(fd, 5);
	if (ret == -1)
	{
		perror("Error listening in inet socket");
		exit(1);
	}

	return fd;
}

int init_vsock_socket(int port)
{
	struct sockaddr_vm vsock;
	int fd;

	memset(&vsock, 0, sizeof(vsock));
	vsock.svm_family = AF_VSOCK;
	vsock.svm_cid = VMADDR_CID_ANY;
	vsock.svm_port = port;

	fd = socket(AF_VSOCK, SOCK_STREAM, 0);
	bind(fd, (struct sockaddr *) &vsock, sizeof(vsock));
	if (listen(fd, 4) != 0) {
		perror("Couldn't listen on vsock\n");
		exit(-1);
	}

	return fd;
}

void find_base_dir(struct environment *env)
{
	char *base_dir = NULL;
	int ret;
	int len;
	pid_t pid;

	pid = getpid();
	snprintf(buf, BUFFER_SIZE, "/proc/%d/exe", pid);
	ret = readlink(buf, scratch, BUFFER_SIZE);
	if (ret == -1) {
		perror("Couldn't read link \"/proc/PID/exe\"");
		exit(-1);
	}

	base_dir = dirname(scratch);
	if (base_dir == NULL) {
		printf("Couldn't find base directory\n");
		exit(-1);
	}
	len = strlen(base_dir) + 1;
	env->base_dir = malloc(len);
	strncpy(env->base_dir, base_dir, len);
}

int open_fifo(struct environment *env, char *name)
{
	struct stat st = {0};
	int fd;

	snprintf(buf, BUFFER_SIZE, "%s%s%s", env->base_dir, INSTANCE_DIR, name);
	if (stat(buf, &st) == -1) {
		if (mkfifo(buf, 0660) == -1) {
			printf("Couldn't create fifo %s: %s", buf, strerror(errno));
			exit(-1);
		}
	}
	fd = open(buf, O_RDWR);
	if (fd < 0) {
		printf("Couldn't open file %s: %s", buf, strerror(errno));
		exit(-1);
	}

	return fd;
}

void create_qemu_directory(char *base_dir)
{
	struct stat st = {0};

	snprintf(buf, BUFFER_SIZE, "%s%s", base_dir, INSTANCE_DIR);
	if (stat(buf, &st) == -1) {
		if (mkdir(buf, 0700) != 0) {
			perror("Error creating QEMU directory");
			exit(-1);
		}
	}
}

void prepare_environment(struct environment *env, char *base_dir)
{
	struct sockaddr_vm vsock;
	struct sockaddr *sa;
	int vsock_fd;
	char **envp;
	int len;

	buf = malloc(BUFFER_SIZE);
	scratch = malloc(BUFFER_SIZE);

	if (base_dir != NULL) {
		env->base_dir = base_dir;
	} else {
		find_base_dir(env);
	}

	if (chdir(env->base_dir) == -1) {
		perror("Couldn't switch to CVD directory");
		exit(-1);
	}

	create_qemu_directory(env->base_dir);

	env->km_in = open_fifo(env, "keymaster_fifo_vm.in");
	env->km_out = open_fifo(env, "keymaster_fifo_vm.out");
	env->gk_in = open_fifo(env, "gatekeeper_fifo_vm.in");
	env->gk_out = open_fifo(env, "gatekeeper_fifo_vm.out");
	env->kn_in = open_fifo(env, "kernel-log-pipe");
	env->lc_in = open_fifo(env, "logcat-pipe");
	env->bt_in = open_fifo(env, "bt_fifo_vm.in");
	env->bt_out = open_fifo(env, "bt_fifo_vm.out");

	env->adb_sock = init_inet_socket(env);

	snprintf(buf, BUFFER_SIZE, "%s%sconfui.sock", env->base_dir, INSTANCE_DIR);
	env->cu_sock = init_unix_socket(env, buf);

	if (env->vsock_user) {
		snprintf(buf, BUFFER_SIZE, "%s%svhost-user-vsock.uds_9600", env->base_dir, INSTANCE_DIR);
		env->ms_vsock = init_unix_socket(env, buf);
		snprintf(buf, BUFFER_SIZE, "%s%svhost-user-vsock.uds_6800", env->base_dir, INSTANCE_DIR);
		env->cs_vsock = init_unix_socket(env, buf);
	} else {
		env->ms_vsock = init_vsock_socket(9600);
		env->cs_vsock = init_vsock_socket(6800);
	}

	pipe(env->adb_pipe);
	pipe(env->kevs_pipe);

	envp = malloc(4 * sizeof(char *));

	snprintf(buf, BUFFER_SIZE, "HOME=%s", env->base_dir);
	len = strlen(buf) + 1;
	envp[0] = malloc(len);
	strncpy(envp[0], buf, len);

	snprintf(buf, BUFFER_SIZE, "ANDROID_TZDATA_ROOT=%s", env->base_dir);
	len = strlen(buf) + 1;
	envp[1] = malloc(len);
	strncpy(envp[1], buf, len);

	snprintf(buf, BUFFER_SIZE, "ANDROID_ROOT=%s", env->base_dir);
	len = strlen(buf) + 1;
	envp[2] = malloc(len);
	strncpy(envp[2], buf, len);

	env->envp = envp;
}

int add_base_args(int arg_idx, char args_base[][32], char **argv)
{
	char *arg;
	int len;
	int i;

	for (i = 0; args_base[i][0] != '\0'; i++) {
		arg = args_base[i];
		len = strlen(arg) + 1;
		argv[arg_idx] = malloc(len);
		strncpy(argv[arg_idx], arg, len);
		arg_idx++;
	}

	return arg_idx;
}

int add_fd_arg(int arg_idx, char *fmt, int fd, char **argv)
{
	int len;

	snprintf(buf, BUFFER_SIZE, fmt, fd);
	len = strlen(buf) + 1;
	argv[arg_idx] = malloc(len);
	strncpy(argv[arg_idx], buf, len);

	return arg_idx + 1;
}

void start_adb_connector(struct environment *env)
{
	char *const argv[] =
        {
			"adb_connector",
			"--addresses=0.0.0.0:6520",
			0
        };

	snprintf(buf, BUFFER_SIZE, "%s/bin/%s", env->base_dir, argv[0]);
	execve(buf, &argv[0], env->envp);
}

void uds_tcp_proxy(struct environment *env)
{
	struct sockaddr_un local;
	fd_set fds;
	char idata[SOCK_BUF_SIZE];
	char udata[SOCK_BUF_SIZE];
	int idata_len = 0;
	int udata_len = 0;
	int last_fd;
	int isock;
	int usock;
	int ret;
	int len;
	int n;

	isock = accept(env->adb_sock, NULL, NULL);
	if (isock < 0) {
		perror("vsock_proxy: error accepting inet");
		return;
	}

	usock = socket(AF_UNIX, SOCK_STREAM, 0);
	if(usock == -1) {
		perror("vsock_proxy: error creating unix socket");
		return;
	}
	local.sun_family = AF_UNIX;
	snprintf(buf, BUFFER_SIZE, "%s%svhost-user-vsock.uds", env->base_dir, INSTANCE_DIR);
	strcpy(local.sun_path, buf);
	len = strlen(local.sun_path) + sizeof(local.sun_family);
	ret = connect(usock, (struct sockaddr *) &local, len);
	if (ret != 0) {
		perror("Error connecting to UDS backend");
		close(isock);
		return;
	}
	write(usock, "CONNECT 5555\n", 13);
	n = read(usock, &buf, 8);
	if (n != 8 || memcmp(&buf, "OK 5555\n", 8) != 0) {
		printf("Invalid answer to CONNECT\n");
		close(isock);
		close(usock);
		return;
	}

	last_fd = isock > usock ? isock : usock;

	while (1) {
		if (idata_len) {
			n = write(usock, &idata[0], idata_len);
			idata_len -= n;
		}
		if (udata_len) {
			n = write(isock, &udata[0], udata_len);
			udata_len -= n;
		}

		FD_ZERO(&fds);

		if (idata_len < SOCK_BUF_SIZE) {
			FD_SET(isock, &fds);
		}
		if (udata_len < SOCK_BUF_SIZE) {
			FD_SET(usock, &fds);
		}

		ret = select(last_fd + 1, &fds, 0, 0, NULL);
		if (ret <= 0) {
			perror("vsock_proxy: error in select");
			break;
		}

		if (FD_ISSET(isock, &fds)) {
			n = read(isock, &idata[idata_len], SOCK_BUF_SIZE - idata_len);
			if (n > 0) {
				idata_len += n;
			} else {
				perror("vsock_proxy: error reading from isock");
				break;
			}
		}

		if (FD_ISSET(usock, &fds)) {
			n = read(usock, &udata[udata_len], SOCK_BUF_SIZE - udata_len);
			if (n > 0) {
				udata_len += n;
			} else {
				perror("vsock_proxy: error reading from usock");
				break;
			}
		}
	}

	close(usock);
	close(isock);
}

void start_vsock_proxy_stub(struct environment *env)
{
	while (1) {
		uds_tcp_proxy(env);
	}
}

void start_vsock_proxy_real(struct environment *env)
{
	int arg_len = 9;
	int arg_idx = 0;
	char **argv;
	char args_base[][32] = {
		"socket_vsock_proxy\0",
		"--server_type=tcp\0",
		"--client_type=vsock\0",
		"--client_vsock_port=5555\0",
		"--client_vsock_id=3\0",
		"--label=adb\0",
		"--start_event_id=5\0",
		0
	};

	argv = malloc((arg_len + 1) * sizeof(char *));
	argv[arg_len] = 0;

	arg_idx = add_base_args(arg_idx, args_base, argv);
	arg_idx = add_fd_arg(arg_idx, "--events_fd=%d", env->adb_pipe[0], argv);
	arg_idx = add_fd_arg(arg_idx, "--server_fd=%d", env->adb_sock, argv);

	assert(arg_idx == arg_len);

	snprintf(buf, BUFFER_SIZE, "%s/bin/%s", env->base_dir, &args_base[0][0]);
	execve(buf, argv, env->envp);
}

void start_vsock_proxy(struct environment *env)
{
	if (env->vsock_user) {
		start_vsock_proxy_stub(env);
	} else {
		start_vsock_proxy_real(env);
	}
}

void start_config_server_real(struct environment *env)
{
	int arg_len = 2;
	int arg_idx = 0;
	char **argv;
	char args_base[][32] = {
		"config_server\0",
		0
	};

	argv = malloc((arg_len + 1) * sizeof(char *));
	argv[arg_len] = 0;

	arg_idx = add_base_args(arg_idx, args_base, argv);
	arg_idx = add_fd_arg(arg_idx, "--server_fd=%d", env->cs_vsock, argv);

	assert(arg_idx == arg_len);

	snprintf(buf, BUFFER_SIZE, "%s/bin/%s", env->base_dir, &args_base[0][0]);
	execve(buf, argv, env->envp);
}

void start_config_server_stub(struct environment *env)
{
	int ret;
	int sock;

	ret = listen(env->cs_vsock, 0);
	if (ret != 0) {
		perror("config_server (listen)");
		return;
	}

	while (1) {
		sock = accept(env->cs_vsock, NULL, NULL);
		if (sock >= 0) {
			write(sock, CONFIG_SERVER_DATA, 68);
			close(sock);
		}
	}
}

void start_config_server(struct environment *env)
{
	if (env->real_config_server) {
		start_config_server_real(env);
	} else {
		start_config_server_stub(env);
	}
}

void start_tcp_connector(struct environment *env)
{
	int arg_len = 5;
	int arg_idx = 0;
	char **argv;
	char args_base[][32] = {
		"tcp_connector\0",
		"-data_port=7300\0",
		"-buffer_size=2058\0",
		0
	};

	argv = malloc((arg_len + 1) * sizeof(char *));
	argv[arg_len] = 0;

	arg_idx = add_base_args(arg_idx, args_base, argv);
	arg_idx = add_fd_arg(arg_idx, "-fifo_in=%d", env->bt_out, argv);
	arg_idx = add_fd_arg(arg_idx, "-fifo_out=%d", env->bt_in, argv);

	assert(arg_idx == arg_len);

	snprintf(buf, BUFFER_SIZE, "%s/bin/%s", env->base_dir, &args_base[0][0]);
	execve(buf, argv, env->envp);
}

void start_kernel_monitor(struct environment *env)
{
	int arg_len = 3;
	int arg_idx = 0;
	char **argv;
	char args_base[][32] = {
		"kernel_log_monitor\0",
		0
	};

	argv = malloc((arg_len + 1) * sizeof(char *));
	argv[arg_len] = 0;

	arg_idx = add_base_args(arg_idx, args_base, argv);
	arg_idx = add_fd_arg(arg_idx, "-log_pipe_fd=%d", env->kn_in, argv);
	arg_idx = add_fd_arg(arg_idx, "-subscriber_fds=%d,%d", env->adb_pipe[1], argv);

	assert(arg_idx == arg_len);

	snprintf(buf, BUFFER_SIZE, "%s/bin/%s", env->base_dir, &args_base[0][0]);
	execve(buf, argv, env->envp);
}

void start_logcat_receiver(struct environment *env)
{
	int arg_len = 2;
	int arg_idx = 0;
	char **argv;
	char args_base[][32] = {
		"logcat_receiver\0",
		0
	};

	argv = malloc((arg_len + 1) * sizeof(char *));
	argv[arg_len] = 0;

	arg_idx = add_base_args(arg_idx, args_base, argv);
	arg_idx = add_fd_arg(arg_idx, "-log_pipe_fd=%d", env->lc_in, argv);

	snprintf(buf, BUFFER_SIZE, "%s/bin/%s", env->base_dir, &args_base[0][0]);
	execve(buf, argv, env->envp);
}

void start_secure_env(struct environment *env)
{
	int arg_len = 9;
	int arg_idx = 0;
	char **argv;
	char args_base[][32] = {
		"secure_env\0",
		"-keymint_impl=rust-tpm\0",
		"-gatekeeper_impl=tpm\0",
		0,
	};

	argv = malloc((arg_len + 1) * sizeof(char *));
	argv[arg_len] = 0;

	arg_idx = add_base_args(arg_idx, args_base, argv);
	arg_idx = add_fd_arg(arg_idx, "-keymaster_fd_in=%d", env->km_out, argv);
	arg_idx = add_fd_arg(arg_idx, "-keymaster_fd_out=%d", env->km_in, argv);
	arg_idx = add_fd_arg(arg_idx, "-gatekeeper_fd_in=%d", env->gk_out, argv);
	arg_idx = add_fd_arg(arg_idx, "-gatekeeper_fd_out=%d", env->gk_in, argv);
	arg_idx = add_fd_arg(arg_idx, "-kernel_events_fd=%d", env->kevs_pipe[0], argv);
	arg_idx = add_fd_arg(arg_idx, "-confui_server_fd=%d", env->cu_sock, argv);

	assert(arg_idx == arg_len);

	snprintf(buf, BUFFER_SIZE, "%s/bin/%s", env->base_dir, &args_base[0][0]);
	execve(buf, argv, env->envp);
}

void start_root_canal(struct environment *env)
{
	char *const argv[] = {
		"root-canal",
		"--test_port=7500",
		"--hci_port=7300",
		"--link_port=7400",
		"--link_ble_port=7600",
		0
	};

	snprintf(buf, BUFFER_SIZE, "%s/bin/%s", env->base_dir, argv[0]);
	execve(buf, &argv[0], env->envp);
}

void start_modem_simulator(struct environment *env)
{
	int arg_len = 3;
	int arg_idx = 0;
	char **argv;
	char args_base[][32] = {
		"modem_simulator\0",
		"-sim_type=1\0",
		0
	};

	argv = malloc((arg_len + 1) * sizeof(char *));
	argv[arg_len] = 0;

	arg_idx = add_base_args(arg_idx, args_base, argv);
	arg_idx = add_fd_arg(arg_idx, "-server_fds=%d", env->ms_vsock, argv);

	snprintf(buf, BUFFER_SIZE, "%s/bin/%s", env->base_dir, &args_base[0][0]);
	execve(buf, argv, env->envp);
}

#define NCHILDREN 9

pid_t children[NCHILDREN];

void cleanup(int dummy) {
	int i = 0;

	for (i = 0; i < NCHILDREN; ++i) {
		kill(children[i], SIGTERM);
	}

	exit(0);
}

void print_usage(char **argv) {
	printf("Usage: %s [OPTIONS] <CVD_DIR>\n\n", argv[0]);
	printf("Options:\n");
	printf("  -u         use vhost-user-vsock instead of vhost-vsock\n");
	printf("  -r         use the real config_server instead of a stub\n");
	exit(1);
}

int main(int argc, char **argv)
{
	void (*service[NCHILDREN])(struct environment *env) = {
		start_adb_connector, start_vsock_proxy, start_tcp_connector,
		start_config_server, start_kernel_monitor, start_logcat_receiver,
		start_secure_env, start_root_canal, start_modem_simulator
	};
	struct environment env;
	pid_t child;
	char *base_dir;
	int vsock_user = 0;
	int real_config_server = 0;
	int i;
	int c;

	while ((c = getopt (argc, argv, "ur")) != -1) {
		switch (c)
			{
			case 'u':
				vsock_user = 1;
				break;
			case 'r':
				real_config_server = 1;
				break;
			default:
				print_usage(argv);
			}
	}

	if (optind == argc - 1) {
		base_dir = argv[optind];
	} else {
		print_usage(argv);
	}

	env.vsock_user = vsock_user;
	env.real_config_server = real_config_server;
	prepare_environment(&env, base_dir);

	signal(SIGINT, cleanup);
	signal(SIGTERM, cleanup);

	for (i = 0; i < NCHILDREN; i++) {
		child = fork();
		if (child == 0) {
			(*service[i])(&env);
			exit(1);
		} else {
			printf("Process %d started with PID %d\n", i, child);
			children[i] = child;
		}
	}

	while (i > 0) {
		child = waitpid(-1, NULL, 0);
		printf("Process with PID=%d exited\n", child);
		i--;
	}

	return 0;
}
