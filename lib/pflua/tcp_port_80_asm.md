# Generated ASM code

Currently the following filter: 

```
tcp port 80
```

yields the following assembly (x86) code:

```asm
0bca9db1  mov dword [0x41dd94a0], 0x38
0bca9dbc  movsd xmm6, [0x418121d0]
0bca9dc5  cmp dword [rdx+0x4], -0x09
0bca9dc9  jnz 0x0bca0010    ->0
0bca9dcf  cmp dword [rdx+0xc], -0x0b
0bca9dd3  jnz 0x0bca0010    ->0
0bca9dd9  mov r14d, [rdx+0x8]
0bca9ddd  cmp dword [rdx+0x14], 0xfffeffff
0bca9de4  jnb 0x0bca0010    ->0
0bca9dea  movsd xmm7, [rdx+0x10]
0bca9def  cmp dword [rdx], 0x40a2c170
0bca9df5  jnz 0x0bca0010    ->0
0bca9dfb  ucomisd xmm7, xmm6
0bca9dff  jb 0x0bca0014 ->1
0bca9e05  mov ebp, [0x40a2c178]
0bca9e0c  cmp dword [rbp+0x1c], +0x3f
0bca9e10  jnz 0x0bca0018    ->2
0bca9e16  mov ebx, [rbp+0x14]
0bca9e19  mov rdi, 0xfffffffb41de0c70
0bca9e23  cmp rdi, [rbx+0x320]
0bca9e2a  jnz 0x0bca0018    ->2
0bca9e30  cmp dword [rbx+0x31c], -0x0c
0bca9e37  jnz 0x0bca0018    ->2
0bca9e3d  mov ebp, [rbx+0x318]
0bca9e43  cmp dword [rbp+0x1c], +0x1f
0bca9e47  jnz 0x0bca0018    ->2
0bca9e4d  mov r15d, [rbp+0x14]
0bca9e51  mov rdi, 0xfffffffb41dea978
0bca9e5b  cmp rdi, [r15+0x98]
0bca9e62  jnz 0x0bca0018    ->2
0bca9e68  cmp dword [r15+0x94], -0x09
0bca9e70  jnz 0x0bca0018    ->2
0bca9e76  movzx ebp, word [r14+0x6]
0bca9e7b  cmp ebp, 0xac
0bca9e81  jnz 0x0bca0018    ->2
0bca9e87  mov rbp, [r14+0x8]
0bca9e8b  cmp dword [r15+0x90], 0x41dec420
0bca9e96  jnz 0x0bca0018    ->2
0bca9e9c  movzx r13d, word [rbp+0xc]
0bca9ea1  cmp r13d, +0x08
0bca9ea5  jnz 0x0bca001c    ->3
0bca9eab  movzx r12d, byte [rbp+0x17]
0bca9eb0  cmp r12d, +0x06
0bca9eb4  jnz 0x0bca0020    ->4
0bca9eba  movzx edi, word [rbp+0x14]
0bca9ebe  mov rsi, 0xfffffffb41ddfd00
0bca9ec8  cmp rsi, [rbx+0x398]
0bca9ecf  jnz 0x0bca0024    ->5
0bca9ed5  cmp dword [rbx+0x394], -0x0c
0bca9edc  jnz 0x0bca0024    ->5
0bca9ee2  mov ebx, [rbx+0x390]
0bca9ee8  cmp dword [rbx+0x1c], +0x0f
0bca9eec  jnz 0x0bca0024    ->5
0bca9ef2  mov ebx, [rbx+0x14]
0bca9ef5  mov rsi, 0xfffffffb41de0138
0bca9eff  cmp rsi, [rbx+0x170]
0bca9f06  jnz 0x0bca0024    ->5
0bca9f0c  cmp dword [rbx+0x16c], -0x09
0bca9f13  jnz 0x0bca0024    ->5
0bca9f19  cmp dword [rbx+0x168], 0x41de0110
0bca9f23  jnz 0x0bca0024    ->5
0bca9f29  mov esi, edi
0bca9f2b  and esi, 0xff1f
0bca9f31  jnz 0x0bca0028    ->6
0bca9f37  movzx ecx, byte [rbp+0xe]
0bca9f3b  mov eax, ecx
0bca9f3d  and eax, +0x0f
0bca9f40  mov r15, 0xfffffffb41ddffd0
0bca9f4a  cmp r15, [rbx+0x140]
0bca9f51  jnz 0x0bca002c    ->7
0bca9f57  cmp dword [rbx+0x13c], -0x09
0bca9f5e  jnz 0x0bca002c    ->7
0bca9f64  cmp dword [rbx+0x138], 0x41ddffa8
0bca9f6e  jnz 0x0bca002c    ->7
0bca9f74  mov r11d, ecx
0bca9f77  shl r11d, 0x02
0bca9f7b  and r11d, +0x3c
0bca9f7f  mov ebx, r11d
0bca9f82  add ebx, +0x10
0bca9f85  jo 0x0bca002c ->7
0bca9f8b  xorps xmm6, xmm6
0bca9f8e  cvtsi2sd xmm6, ebx
0bca9f92  ucomisd xmm7, xmm6
0bca9f96  jb 0x0bca0030 ->8
0bca9f9c  mov r10d, r11d
0bca9f9f  add r10d, +0x0e
0bca9fa3  jo 0x0bca0034 ->9
0bca9fa9  movsxd r15, r10d
0bca9fac  movzx r9d, word [r15+rbp]
0bca9fb1  cmp r9d, 0x5000
0bca9fb8  jz 0x0bca0038 ->10
0bca9fbe  mov r15d, r11d
0bca9fc1  add r15d, +0x12
0bca9fc5  jo 0x0bca003c ->11
0bca9fcb  xorps xmm6, xmm6
0bca9fce  cvtsi2sd xmm6, r15d
0bca9fd3  ucomisd xmm7, xmm6
0bca9fd7  jb 0x0bca0040 ->12
0bca9fdd  movsxd rbx, ebx
0bca9fe0  movzx ebp, word [rbx+rbp]
0bca9fe4  cmp ebp, 0x5000
0bca9fea  jz 0x0bca0048 ->14
0bca9ff0  xor eax, eax
0bca9ff2  mov ebx, 0x41df874c
0bca9ff7  mov r14d, 0x41dd9f78
0bca9ffd  jmp 0x0041e288
```
