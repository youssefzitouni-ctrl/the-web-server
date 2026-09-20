.intel_syntax noprefix
.global _start

# ================================================================
# HTTP SERVER
# ================================================================

_start:
    # ------------------------------------------------------------
    # socket(AF_INET, SOCK_STREAM, IPPROTO_IP)
    # ------------------------------------------------------------
    mov rax, 41
    mov rdi, 2
    mov rsi, 1
    xor rdx, rdx
    syscall

    # ------------------------------------------------------------
    # Build sockaddr_in on the stack
    # ------------------------------------------------------------
    sub rsp, 16
    mov word ptr [rsp], 2
    mov word ptr [rsp+2], 0x5000
    mov dword ptr [rsp+4], 0
    mov qword ptr [rsp+8], 0

    # bind(server_fd, sockaddr, 16)
    mov rax, 49
    mov rdi, 3
    mov rsi, rsp
    mov rdx, 16
    syscall

    # listen(server_fd, 0)
    mov rax, 50
    mov rdi, 3
    xor rsi, rsi
    syscall

    # ------------------------------------------------------------
    # Allocate buffers
    # ------------------------------------------------------------
    sub rsp, 1024
    mov r13, rsp                  # request buffer

    sub rsp, 4096
    mov r14, rsp                  # file buffer

# ================================================================
# ACCEPT LOOP
# ================================================================

lp:
    # accept(server_fd, NULL, NULL)
    mov rax, 43
    mov rdi, 3
    xor rsi, rsi
    xor rdx, rdx
    syscall
    mov r12, rax                  # client fd

    # fork()
    mov rax, 57
    syscall

    cmp rax, 0
    je child

    # Parent closes client and accepts the next connection
    mov rax, 3
    mov rdi, r12
    syscall
    jmp lp

# ================================================================
# CHILD PROCESS
# ================================================================

child:
    # Child closes listening socket
    mov rax, 3
    mov rdi, 3
    syscall

    # read(client, request, 1024)
    xor rax, rax
    mov rdi, r12
    mov rsi, r13
    mov rdx, 1024
    syscall

    # POST starts with 'P'; otherwise handle as GET
    cmp byte ptr [r13], 'P'
    je post

# ================================================================
# GET
# ================================================================

get:
    # Pathname starts after "GET "
    lea r15, [r13+4]
    call snip

    # open(pathname, O_RDONLY)
    mov rdi, rax
    xor rsi, rsi
    mov rax, 2
    syscall
    mov rbx, rax                  # file fd

    # read(file, file_buffer, 4096)
    xor rax, rax
    mov rdi, rbx
    mov rsi, r14
    mov rdx, 4096
    syscall
    mov r10, rax                  # bytes read

    # close(file)
    mov rax, 3
    mov rdi, rbx
    syscall

    # write(client, response, 19)
    mov rax, 1
    mov rdi, r12
    lea rsi, [response]
    mov rdx, 19
    syscall

    # write(client, file_buffer, bytes_read)
    mov rax, 1
    mov rdi, r12
    mov rsi, r14
    mov rdx, r10
    syscall

    jmp child_done

# ================================================================
# POST
# ================================================================

post:
    # Pathname starts after "POST "
    lea r15, [r13+5]
    call snip

    # open(pathname, O_WRONLY | O_CREAT, 0777)
    mov rdi, rax
    mov rsi, 65                   # O_WRONLY | O_CREAT
    mov rdx, 0777
    mov rax, 2
    syscall
    mov rbx, rax                  # file fd

    # ------------------------------------------------------------
    # Find Content-Length
    # ------------------------------------------------------------
    lea r9, [r13]
    call find_length
    mov r8, rdx                   # save Content-Length

    # ------------------------------------------------------------
    # Find the blank line separating headers from body
    # ------------------------------------------------------------
    lea r9, [r13]

find_body:
    cmp dword ptr [r9], 0x0a0d0a0d
    je body_found

    inc r9
    jmp find_body

body_found:
    # Body starts four bytes after \r\n\r\n
    lea rsi, [r9+4]
    mov rdx, r8                   # Content-Length

    # write(file, body, Content-Length)
    mov rax, 1
    mov rdi, rbx
    syscall

    # close(file)
    mov rax, 3
    mov rdi, rbx
    syscall

    # write(client, response, 19)
    mov rax, 1
    mov rdi, r12
    lea rsi, [response]
    mov rdx, 19
    syscall

    jmp child_done

# ================================================================
# SNIP PATHNAME
#
# Input:  r15 = pathname start
# Output: rax = pathname start
# Replaces the first trailing space with NUL.
# ================================================================

snip:
    mov rax, r15

snip_loop:
    cmp byte ptr [r15], 0x20
    je snip_done

    inc r15
    jmp snip_loop

snip_done:
    mov byte ptr [r15], 0
    ret

# ================================================================
# FIND CONTENT-LENGTH
#
# Input:  r9 = request start
# Output: rdx = parsed Content-Length
# ================================================================

find_length:
    cmp dword ptr [r9], 0x746e6f43       # "Cont"
    jne next

    cmp dword ptr [r9+4], 0x2d746e65      # "ent-"
    jne next

    cmp dword ptr [r9+8], 0x676e654c      # "Leng"
    jne next

    cmp dword ptr [r9+12], 0x203a6874     # "th: "
    je found_length

next:
    inc r9
    jmp find_length

found_length:
    add r9, 16                            # first digit
    xor rdx, rdx                          # result = 0

parse:
    movzx rax, byte ptr [r9]

    cmp al, '0'
    jb done

    cmp al, '9'
    ja done

    sub al, '0'
    imul rdx, rdx, 10

    movzx rax, al
    add rdx, rax

    inc r9
    jmp parse

done:
    ret

# ================================================================
# CHILD CLEANUP / EXIT
# ================================================================

child_done:
    # close(client)
    mov rax, 3
    mov rdi, r12
    syscall

    # exit(0)
    mov rax, 60
    xor rdi, rdi
    syscall

# ================================================================
# READ-ONLY DATA
# ================================================================

.section .rodata

response:
    .ascii "HTTP/1.0 200 OK\r\n\r\n"
