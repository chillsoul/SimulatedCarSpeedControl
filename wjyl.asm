;数据段
DATA SEGMENT
    IO8255_A    EQU 288H
    IO8255_B    EQU 289H
    IO8255_C    EQU 28AH
    IO8255_K    EQU 28BH
    LEDTABLE    DB  3FH,06H,5BH,4FH,66H,6DH,7DH,07H,7FH,6FH ;段码
    KEYTABLE    DB  077h,07Bh,07Dh,07Eh,0B7h,0BBh,0BDh,0BEh
                DB  0D7h,0DBh,0DDh,0DEh,0E7h,0EBh,0EDh,0EEh ;键盘扫描码表
    KEY         DB  '0123456789ABCDEF'
    buffer_bin  DB  0,0,0 ;LED输出缓冲区，个十百位
    buffer_hex  DW  0 ;LED输出缓冲区，十六位
    LED_bit     DB  ? ;位码值缓存
    global_state DB 0 ;=0停止，1启动第一档,2第二档，3第三档
    limit       DW  0,0 ;限速设置，最低，最高
    speed_state DB  0 ;=0最低速，<0减速，>0加速
    abs_a       DB  0 ;=0最低速，其余值为加速度绝对值
DATA ENDS

;代码段
CODE SEGMENT
    ASSUME CS:CODE,DS:DATA
START: ;程序起始
    MOV AX,DATA
    MOV DS,AX
    MOV DX,IO8255_K
    MOV AL,10000001B ;将8255设为A、B口输出、C口上半输出下半输入
    OUT DX,AL
MAIN: ;主要循环
    call scan4x4Keyboard ;扫描键盘，控制状态变量
    call setSpeed
    ;检测是否退出
    MOV AH,01
    INT 16H
    CMP AL,1BH ;判断是否键入ESC
    JE EXIT
    JMP MAIN
;扫描键盘输入
scan4x4Keyboard PROC
    ;寄存器保存
    PUSH DX
    PUSH AX
    PUSH BX
    PUSH SI
    PUSH DI
    PUSH CX
    ;反转法识别键盘
    MOV DX,IO8255_C
    MOV AL,00000000B ;八位为行3210列3210，此处使行输出0
    OUT DX,AL
    IN  AL,DX ;读取列值到低四位
    CMP AL,0FH ;判断低四位是否有0
    JZ  endOfScan4x4Keyboard
STEP1:
    PUSH AX
    PUSH AX
    MOV DX,IO8255_K
    MOV AL,10001000B ;将8255设为A、B口输出、C口上半输入下半输出
    OUT DX,AL
    MOV DX,IO8255_C
    POP AX    ;恢复上次扫描到的列值，低四位有效
    OUT DX,AL ;将列值输出到列
    IN  AL,DX ;读取行值到高四位
    AND AL,0F0H;清空低四位
    POP BX    ;再次恢复上次扫描到的列值，低四位有效
    AND BL,0FH;清空高四位
    MOV AH,AL ;行值移到AH高4位
    ADD AH,BL ;列值移到AH低4位，此时行列值合并到AH
    MOV SI,OFFSET KEYTABLE
    MOV DI,OFFSET KEY
    MOV CX,16 ;4x4键盘共16个键需要比对
STEP2:
    CMP AH,[SI]
    JZ  STEP3
    INC SI
    INC DI
    LOOP STEP2
    ;未找到，恢复8255初始模式
    MOV DX,IO8255_K
    MOV AL,10000001B ;将8255设为A、B口输出、C口上半输出下半输入
    OUT DX,AL
    JMP endOfScan4x4Keyboard ;未找到键
STEP3:
    MOV DL,[DI]
    CMP DL,'1'
    JZ  ENABLE_STATE
ENABLE_STATE:
    CMP [global_state],1 ;如果是第一次启动，那么把速度状态设为0表示初速度5
    JE  SWITCHL1
    MOV [speed_state],0
SWITCHL1:
    MOV [global_state],1
    MOV limit[0],5H
    MOV limit[1],25H
    JMP endOfScan4x4Keyboard

    CMP DL,'2'
    JZ  SWITCHL2
    CMP DL,'3'
    JZ  SWITCHL3
SWITCHL2:
    MOV [global_state],2 ;第二档
    MOV limit[0],25H
    MOV limit[1],60H
    JMP endOfScan4x4Keyboard
SWITCHL3:
    MOV [global_state],3 ;第三档
    MOV limit[0],60H
    MOV limit[1],120H
    JMP endOfScan4x4Keyboard

    CMP DL,'A'
    JZ  SPEEDUPL1
    CMP DL,'B'
    JZ  SPEEDUPL2
    CMP DL,'C'
    JZ  SPEEDDOWNL1
    CMP DL,'D'
    JZ  SPEEDDOWNL2
SPEEDUPL1:
    MOV [speed_state],1 ;加速
    MOV [abs_a],30 ;慢加速
    JMP endOfScan4x4Keyboard
SPEEDUPL2:
    MOV [speed_state],1 ;加速
    MOV [abs_a],15 ;快加速
    JMP endOfScan4x4Keyboard
SPEEDDOWNL1:
    MOV [speed_state],-1 ;加速
    MOV [abs_a],30 ;慢刹车
    JMP endOfScan4x4Keyboard
SPEEDDOWNL2:
    MOV [speed_state],-1 ;加速
    MOV [abs_a],15 ;急刹车
    JMP endOfScan4x4Keyboard

endOfScan4x4Keyboard:
    ;寄存器恢复
    POP CX
    POP DI
    POP SI
    POP BX
    POP AX
    POP DX
    RET
scan4x4Keyboard ENDP
;显示数码管
lightLED PROC
    ;保护寄存器
    PUSH DI
    PUSH BX
    PUSH CX
    PUSH SI
    PUSH DX
    ;软件延时实现单端复用
    MOV DI,OFFSET buffer_bin
    MOV CH,0
    MOV CL,abs_a
LEDLOOP1:
    MOV BH,02
LEDLOOP2:
    MOV [LED_bit],BH ;保存位码以节约BH寄存器
    PUSH DI
    MOV BH,0
    MOV BL,LED_bit
    ADD DI,BX
    MOV BL,[DI] ;BL为要显示的数字
    POP DI
    MOV BH,0 ;清空BH以便加法运算
    MOV SI,OFFSET LEDTABLE
    ADD SI,BX ;SI为要输出数字的段码地址
    MOV AL,BYTE PTR [SI] ;AL为要输出的段码
    MOV DX,IO8255_A
    OUT DX,AL
    MOV AL,LED_bit ;使对应数码管亮
    MOV DX,IO8255_B
    OUT DX,AL ;B口输出位码
    PUSH CX
    MOV CX,100
DELAY:
    LOOP DELAY ;延时
    POP CX
    DEC BYTE PTR [LED_bit]
    JNZ LEDLOOP2 ;循环复用驱动多个数码管
    LOOP LEDLOOP1 ;循环延时后再增速度
    ;恢复寄存器
    POP DX
    POP SI
    POP CX
    POP BX
    POP DI
lightLED ENDP
;速度设置
setSpeed PROC
    PUSH AX
    MOV AX,WORD PTR [buffer_hex]
    CMP [global_state],0
    JE  endOfSetSpeed
    CMP [global_state],1
    JE  BASICCHECK
BASICCHECK:
    CMP [speed_state],0
    JE  BASICSPEED
    JA  SETSPEEDUP
    JB  SETSPEEDDOWN
BASICSPEED:
    MOV [buffer_hex],5
    call bufferSync
    JMP endOfSetSpeed
SETSPEEDUP:  
    CMP AX,limit[1] ;等于最高速不加速
    JE endOfSetSpeed
    INC AX
    DAA
    ADC AH,0
    call bufferSync
    JMP endOfSetSpeed
SETSPEEDDOWN:
    CMP AX,limit[0] ;等于最低速不减速
    JE endOfSetSpeed
    DEC AX
    DAS
    call bufferSync
    JMP endOfSetSpeed
endOfSetSpeed:
    POP AX
    RET
setSpeed ENDP
;LED缓冲区同步
bufferSync PROC
    ;保存寄存器
    PUSH AX
    PUSH DX
    MOV AX,[buffer_hex]
    MOV DL,AL
    AND DL,0FH ;取低四位（个位）
    MOV buffer_bin[0],DL
    MOV DL,AL
    AND DL,0F0H ;取高四位（十位）
    MOV buffer_bin[1],DL
    MOV DL,AH
    AND DL,0FH ;取第四位（百位）
    MOV buffer_bin[2],DL
    ;恢复寄存器
    POP DX
    POP AX
bufferSync ENDP
;键入ESC
EXIT PROC
    MOV DX,IO8255_A
    MOV AL,0 ;数码管显示0
    OUT DX,AL
    ;内存变量全部恢复初始化
    MOV [global_state],0
    MOV [speed_state],0
    MOV [abs_a],0
    MOV buffer_bin[0],0
    MOV buffer_bin[1],0
    MOV buffer_bin[2],0
    MOV [buffer_hex],0
    MOV [LED_bit],2
    RET
EXIT ENDP

CODE ENDS
    END START
