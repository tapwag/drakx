/*
 * Guillaume Cottenceau (gc@mandrakesoft.com)
 *
 * Copyright 2000 MandrakeSoft
 *
 * This software may be freely redistributed under the terms of the GNU
 * public license.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 *
 */

/*
 * Portions from Erik Troan <ewt@redhat.com> and Matt Wilson <msw@redhat.com>
 *
 * Copyright 1999 Red Hat, Inc.
 *
 */

#include <alloca.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <netinet/in_systm.h>

#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <netdb.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <sys/types.h>
#include <unistd.h>

#include <netinet/in.h>
#include <netinet/ip.h>
#include <arpa/inet.h>

#include "log.h"
#include "dns.h"
#include "tools.h"

#include "url.h"


#define TIMEOUT_SECS 60
#define BUFFER_SIZE 4096


static int ftp_check_response(int sock, char ** str)
{
	static char buf[BUFFER_SIZE + 1];
	int bufLength = 0; 
	fd_set emptySet, readSet;
	char * chptr, * start;
	struct timeval timeout;
	int bytesRead, rc = 0;
	int doesContinue = 1;
	char errorCode[4];
 
	errorCode[0] = '\0';
    
	do {
		FD_ZERO(&emptySet);
		FD_ZERO(&readSet);
		FD_SET(sock, &readSet);

		timeout.tv_sec = TIMEOUT_SECS;
		timeout.tv_usec = 0;
    
		rc = select(sock + 1, &readSet, &emptySet, &emptySet, &timeout);
		if (rc < 1) {
			if (rc==0) 
				return FTPERR_BAD_SERVER_RESPONSE;
			else
				rc = FTPERR_UNKNOWN;
		} else
			rc = 0;

		bytesRead = read(sock, buf + bufLength, sizeof(buf) - bufLength - 1);

		bufLength += bytesRead;

		buf[bufLength] = '\0';

		/* divide the response into lines, checking each one to see if 
		   we are finished or need to continue */

		start = chptr = buf;

		do {
			while (*chptr != '\n' && *chptr) chptr++;

			if (*chptr == '\n') {
				*chptr = '\0';
				if (*(chptr - 1) == '\r') *(chptr - 1) = '\0';
				if (str) *str = start;

				if (errorCode[0]) {
					if (!strncmp(start, errorCode, 3) && start[3] == ' ')
						doesContinue = 0;
				} else {
					strncpy(errorCode, start, 3);
					errorCode[3] = '\0';
					if (start[3] != '-') {
						doesContinue = 0;
					} 
				}

				start = chptr + 1;
				chptr++;
			} else {
				chptr++;
			}
		} while (*chptr);

		if (doesContinue && chptr > start) {
			memcpy(buf, start, chptr - start - 1);
			bufLength = chptr - start - 1;
		} else {
			bufLength = 0;
		}
	} while (doesContinue && !rc);

	if (*errorCode == '4' || *errorCode == '5') {
		if (!strncmp(errorCode, "550", 3)) {
			return FTPERR_FILE_NOT_FOUND;
		}

		return FTPERR_BAD_SERVER_RESPONSE;
	}

	if (rc) return rc;

	return 0;
}

static int ftp_command(int sock, char * command, char * param)
{
	char buf[500];
	int rc;

	strcpy(buf, command);
	if (param) {
		strcat(buf, " ");
		strcat(buf, param);
	}
	
	strcat(buf, "\r\n");
     
	if (write(sock, buf, strlen(buf)) != strlen(buf)) {
		return FTPERR_SERVER_IO_ERROR;
	}

	if ((rc = ftp_check_response(sock, NULL)))
		return rc;

	return 0;
}

static int get_host_address(const char * host, struct in_addr * address)
{
	if (isdigit(host[0])) {
		if (!inet_aton(host, address)) {
			return FTPERR_BAD_HOST_ADDR;
		}
	} else {
		if (mygethostbyname((char *) host, address)) {
			errno = h_errno;
			return FTPERR_BAD_HOSTNAME;
		}
	}
    
	return 0;
}

int ftp_open_connection(char * host, char * name, char * password, char * proxy)
{
	int sock;
	struct in_addr serverAddress;
	struct sockaddr_in destPort;
	char * buf;
	int rc;
	int port = 21;

	if (!strcmp(name, ""))
		name = "anonymous";

	if (!strcmp(password, ""))
		password = "-drakx@";

	if (strcmp(proxy, "")) {
		buf = alloca(strlen(name) + strlen(host) + 5);
		sprintf(buf, "%s@%s", name, host);
		name = buf;
		host = proxy;
	}

	if ((rc = get_host_address(host, &serverAddress))) return rc;

	sock = socket(AF_INET, SOCK_STREAM, IPPROTO_IP);
	if (sock < 0) {
		return FTPERR_FAILED_CONNECT;
	}

	destPort.sin_family = AF_INET;
	destPort.sin_port = htons(port);
	destPort.sin_addr = serverAddress;

	if (connect(sock, (struct sockaddr *) &destPort, sizeof(destPort))) {
		close(sock);
		return FTPERR_FAILED_CONNECT;
	}

	/* ftpCheckResponse() assumes the socket is nonblocking */
	if (fcntl(sock, F_SETFL, O_NONBLOCK)) {
		close(sock);
		return FTPERR_FAILED_CONNECT;
	}

	if ((rc = ftp_check_response(sock, NULL))) {
		return rc;     
	}

	if ((rc = ftp_command(sock, "USER", name))) {
		close(sock);
		return rc;
	}

	if ((rc = ftp_command(sock, "PASS", password))) {
		close(sock);
		return rc;
	}

	if ((rc = ftp_command(sock, "TYPE", "I"))) {
		close(sock);
		return rc;
	}

	return sock;
}


int ftp_data_command(int sock, char * command, char * param)
{
	int dataSocket;
	struct sockaddr_in dataAddress;
	int i, j;
	char * passReply;
	char * chptr;
	char retrCommand[500];
	int rc;

	if (write(sock, "PASV\r\n", 6) != 6) {
		return FTPERR_SERVER_IO_ERROR;
	}
	if ((rc = ftp_check_response(sock, &passReply)))
		return FTPERR_PASSIVE_ERROR;

	chptr = passReply;
	while (*chptr && *chptr != '(') chptr++;
	if (*chptr != '(') return FTPERR_PASSIVE_ERROR; 
	chptr++;
	passReply = chptr;
	while (*chptr && *chptr != ')') chptr++;
	if (*chptr != ')') return FTPERR_PASSIVE_ERROR;
	*chptr-- = '\0';

	while (*chptr && *chptr != ',') chptr--;
	if (*chptr != ',') return FTPERR_PASSIVE_ERROR;
	chptr--;
	while (*chptr && *chptr != ',') chptr--;
	if (*chptr != ',') return FTPERR_PASSIVE_ERROR;
	*chptr++ = '\0';
    
	/* now passReply points to the IP portion, and chptr points to the
	   port number portion */

	dataAddress.sin_family = AF_INET;
	if (sscanf(chptr, "%d,%d", &i, &j) != 2) {
		return FTPERR_PASSIVE_ERROR;
	}
	dataAddress.sin_port = htons((i << 8) + j);

	chptr = passReply;
	while (*chptr++) {
		if (*chptr == ',') *chptr = '.';
	}

	if (!inet_aton(passReply, &dataAddress.sin_addr)) 
		return FTPERR_PASSIVE_ERROR;

	dataSocket = socket(AF_INET, SOCK_STREAM, IPPROTO_IP);
	if (dataSocket < 0) {
		return FTPERR_FAILED_CONNECT;
	}

	if (!param)
		sprintf(retrCommand, "%s\r\n", command);
	else
		sprintf(retrCommand, "%s %s\r\n", command, param);
	    
	i = strlen(retrCommand);
   
	if (write(sock, retrCommand, i) != i) {
		return FTPERR_SERVER_IO_ERROR;
	}

	if (connect(dataSocket, (struct sockaddr *) &dataAddress, 
		    sizeof(dataAddress))) {
		close(dataSocket);
		return FTPERR_FAILED_DATA_CONNECT;
	}

	if ((rc = ftp_check_response(sock, NULL))) {
		close(dataSocket);
		return rc;
	}

	return dataSocket;
}


static int ftp_get_filesize(int sock, char * remotename)
{
	int size = 0;
	char buf[2000];
	char file[500];
	char * ptr;
	int fd, rc, tot;
	int i;

	strcpy(buf, remotename);
	ptr = buf;
	while (*ptr)
		ptr++;
	ptr--;
	while (*ptr && *ptr != '/')
		ptr--;
	if (!*ptr)
		return -1;
	*ptr = '\0';

	strcpy(file, ptr+1);

	if ((rc = ftp_command(sock, "CWD", buf))) {
		return -1;
	}

	fd = ftp_data_command(sock, "LIST", NULL);
	if (fd <= 0) {
		close(sock);
		return -1;
	}

	ptr = buf;
	while ((tot = read(fd, ptr, sizeof(buf) - (ptr - buf))) != 0)
		ptr += tot;
	*ptr = '\0';
	close(fd);

	if (!(ptr = strstr(buf, file))) {
		log_message("FTP/get_filesize: Bad mood, directory does not contain searched file (%s)", file);
		if (ftp_end_data_command(sock))
			close(sock);
		return -1;
	}

	for (i=0; i<4; i++) {
		while (*ptr && *ptr != ' ')
			ptr--;
		while (*ptr && *ptr == ' ')
			ptr--;
	}
	while (*ptr && *ptr != ' ')
		ptr--;

	if (ptr)
		size = charstar_to_int(ptr+1);
	else
		size = 0;

	if (ftp_end_data_command(sock)) {
		close(sock);
		return -1;
	}

	return size;
}


int ftp_start_download(int sock, char * remotename, int * size)
{
	if ((*size = ftp_get_filesize(sock, remotename)) == -1) {
		log_message("FTP: could not get filesize (trying to continue)");
		*size = 0;
	}
	
	return ftp_data_command(sock, "RETR", remotename);
}


int ftp_end_data_command(int sock)
{
	if (ftp_check_response(sock, NULL))
		return FTPERR_BAD_SERVER_RESPONSE;
	
	return 0;
}

  
int http_download_file(char * hostname, char * remotename)
{
	char * buf;
	struct timeval timeout;
	char headers[4096];
	char * nextChar = headers;
	int checkedCode;
	struct in_addr serverAddress;
	int sock;
	int rc;
	struct sockaddr_in destPort;
	fd_set readSet;

	if ((rc = get_host_address(hostname, &serverAddress))) return rc;

	sock = socket(AF_INET, SOCK_STREAM, IPPROTO_IP);
	if (sock < 0) {
		return FTPERR_FAILED_CONNECT;
	}

	destPort.sin_family = AF_INET;
	destPort.sin_port = htons(80);
	destPort.sin_addr = serverAddress;

	if (connect(sock, (struct sockaddr *) &destPort, sizeof(destPort))) {
		close(sock);
		return FTPERR_FAILED_CONNECT;
	}

	buf = alloca(strlen(remotename) + 20);
	sprintf(buf, "GET %s HTTP/0.9\r\n\r\n", remotename);
	write(sock, buf, strlen(buf));

	/* This is fun; read the response a character at a time until we:

	   1) Get our first \r\n; which lets us check the return code
	   2) Get a \r\n\r\n, which means we're done */

	*nextChar = '\0';
	checkedCode = 0;
	while (!strstr(headers, "\r\n\r\n")) {
		FD_ZERO(&readSet);
		FD_SET(sock, &readSet);

		timeout.tv_sec = TIMEOUT_SECS;
		timeout.tv_usec = 0;
    
		rc = select(sock + 1, &readSet, NULL, NULL, &timeout);
		if (rc == 0) {
			close(sock);
			return FTPERR_SERVER_TIMEOUT;
		} else if (rc < 0) {
			close(sock);
			return FTPERR_SERVER_IO_ERROR;
		}

		if (read(sock, nextChar, 1) != 1) {
			close(sock);
			return FTPERR_SERVER_IO_ERROR;
		}

		nextChar++;
		*nextChar = '\0';

		if (nextChar - headers == sizeof(headers)) {
			close(sock);
			return FTPERR_SERVER_IO_ERROR;
		}

		if (!checkedCode && strstr(headers, "\r\n")) {
			char * start, * end;

			checkedCode = 1;
			start = headers;
			while (!isspace(*start) && *start) start++;
			if (!*start) {
				close(sock);
				return FTPERR_SERVER_IO_ERROR;
			}
			start++;

			end = start;
			while (!isspace(*end) && *end) end++;
			if (!*end) {
				close(sock);
				return FTPERR_SERVER_IO_ERROR;
			}

			*end = '\0';
			if (!strcmp(start, "404")) {
				close(sock);
				return FTPERR_FILE_NOT_FOUND;
			} else if (strcmp(start, "200")) {
				close(sock);
				return FTPERR_BAD_SERVER_RESPONSE;
			}

			*end = ' ';
		}
	}
    
	return sock;
}
