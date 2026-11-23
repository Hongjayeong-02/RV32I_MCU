#!/usr/bin/env python3
"""Generate decoder test vectors: encodings from GNU as, expected from an
independent Python reference of the spec. Writes SIM/TESTBENCH/dec_vectors.vh"""
import subprocess, re, os
HERE = os.path.dirname(os.path.abspath(__file__))
T_O  = os.path.join(HERE, 'build', 'insts.o')
os.makedirs(os.path.join(HERE, 'build'), exist_ok=True)
_S = os.path.join(HERE, 'build', 'insts.S')
with open(_S, 'w') as _f:
    _f.write('.option norvc\n.text\n' + open(os.path.join(HERE, 'insts.txt')).read())
subprocess.run(['riscv64-unknown-elf-as', '-march=rv32i_zicsr', '-mabi=ilp32', _S, '-o', T_O], check=True)


asm = [l.strip() for l in open(os.path.join(HERE,'insts.txt')) if l.strip()]
dump = subprocess.run(['riscv64-unknown-elf-objdump','-d','-M','no-aliases',T_O],
                      capture_output=True, text=True).stdout
words = [int(m.group(1),16) for m in re.finditer(r'^\s+[0-9a-f]+:\s+([0-9a-f]{8})', dump, re.M)]
assert len(words) == len(asm), (len(words), len(asm))

def fld(w,h,l): return (w>>l) & ((1<<(h-l+1))-1)

# extra illegal encodings (built from legal ones)
slli = words[asm.index('slli x5, x6, 31')]
extra = [
 (0x00000000,             'all zero (inst[1:0]!=11)'),
 (slli | (1<<30),         'slli with funct7=0100000'),
 (0x027302b3,             'mul x5,x6,x7 (M ext)'),
 (0x407312b3,             'sll with funct7=0100000'),
 (words[asm.index('beq x1, x2, .+16')] & ~(7<<12) | (2<<12), 'branch funct3=010'),
 (words[asm.index('lw x5, 4(x6)')]     & ~(7<<12) | (3<<12), 'load funct3=011 (ld)'),
 (words[asm.index('lw x5, 4(x6)')]     & ~(7<<12) | (6<<12), 'load funct3=110 (lwu)'),
 (words[asm.index('sw x5, 8(x6)')]     & ~(7<<12) | (3<<12), 'store funct3=011 (sd)'),
 (words[asm.index('jalr x1, 12(x5)')]  | (1<<12),            'jalr funct3=001'),
 (0x0000100f,             'fence.i'),
 (0x10500073,             'wfi'),
 (0x00004073,             'system funct3=100'),
 (0x0000007f,             'opcode 1111111'),
 (0x0000005b,             'opcode 1011011 (custom-2)'),
]

ALU = dict(ADD=0,SUB=1,SLL=2,SLT=3,SLTU=4,XOR=5,SRL=6,SRA=7,OR=8,AND=9,PASSB=10)
def ref(w):
    d = dict(alu=0,asrc=0,bsrc=1,imm=0,u1=0,u2=0,rw=0,wb=0,mr=0,mw=0,br=0,jal=0,jalr=0,
             csr=0,cre=0,cwe=0,ecall=0,ebreak=0,mret=0,ill=0)
    op=fld(w,6,0); f3=fld(w,14,12); f7=fld(w,31,25); rd=fld(w,11,7); rs1=fld(w,19,15)
    rdnz = int(rd!=0)
    if w & 3 != 3: d['ill']=1; return d
    if op==0x37: d.update(alu=ALU['PASSB'],imm=3,rw=rdnz)
    elif op==0x17: d.update(asrc=1,imm=3,rw=rdnz)
    elif op==0x6f: d.update(asrc=1,imm=4,jal=1,wb=2,rw=rdnz)
    elif op==0x67:
        if f3==0: d.update(u1=1,jalr=1,wb=2,rw=rdnz)
        else: d['ill']=1
    elif op==0x63:
        if f3 in (2,3): d['ill']=1
        else: d.update(asrc=1,imm=2,u1=1,u2=1,br=1)
    elif op==0x03:
        if f3 in (0,1,2,4,5): d.update(u1=1,mr=1,wb=1,rw=rdnz)
        else: d['ill']=1
    elif op==0x23:
        if f3 in (0,1,2): d.update(imm=1,u1=1,u2=1,mw=1)
        else: d['ill']=1
    elif op==0x13:
        d.update(u1=1,rw=rdnz)
        m={0:'ADD',2:'SLT',3:'SLTU',4:'XOR',6:'OR',7:'AND'}
        if f3 in m: d['alu']=ALU[m[f3]]
        elif f3==1:
            d['alu']=ALU['SLL']
            if f7!=0: d['ill']=1
        else:
            if f7==0: d['alu']=ALU['SRL']
            elif f7==0x20: d['alu']=ALU['SRA']
            else: d['ill']=1
    elif op==0x33:
        d.update(bsrc=0,u1=1,u2=1,rw=rdnz)
        m={0:'ADD',1:'SLL',2:'SLT',3:'SLTU',4:'XOR',5:'SRL',6:'OR',7:'AND'}
        if f7==0: d['alu']=ALU[m[f3]]
        elif f7==0x20 and f3==0: d['alu']=ALU['SUB']
        elif f7==0x20 and f3==5: d['alu']=ALU['SRA']
        else: d['ill']=1
    elif op==0x0f:
        if f3!=0: d['ill']=1
    elif op==0x73:
        if f3==0:
            if w==0x73: d['ecall']=1
            elif w==0x00100073: d['ebreak']=1
            elif w==0x30200073: d['mret']=1
            else: d['ill']=1
        elif f3==4: d['ill']=1
        else:
            cmd=f3&3
            d.update(csr=1,wb=3,rw=rdnz,imm=5,u1=int(not (f3>>2)),
                     cre= rdnz if cmd==1 else 1,
                     cwe= 1 if cmd==1 else int(rs1!=0))
    else: d['ill']=1
    if d['ill']:
        for k in ('u1','u2','rw','mr','mw','br','jal','jalr','csr','cre','cwe'): d[k]=0
    return d

# packed order MUST match tb: {ill,ecall,ebreak,mret,csr,cre,cwe,br,jal,jalr,mr,mw,rw,wb[1:0],u1,u2,asrc[1:0],bsrc,imm[2:0],alu[3:0]}
def pack(d):
    v=0
    for k,n in [('ill',1),('ecall',1),('ebreak',1),('mret',1),('csr',1),('cre',1),('cwe',1),
                ('br',1),('jal',1),('jalr',1),('mr',1),('mw',1),('rw',1),('wb',2),
                ('u1',1),('u2',1),('asrc',2),('bsrc',1),('imm',3),('alu',4)]:
        v=(v<<n)|d[k]
    return v
# for illegal vectors only the side-effect bits are compared
ILL_MASK = pack(dict(ill=1,ecall=1,ebreak=1,mret=1,csr=1,cre=1,cwe=1,br=1,jal=1,jalr=1,
                     mr=1,mw=1,rw=1,wb=0,u1=1,u2=1,asrc=0,bsrc=0,imm=0,alu=0))
FULL = (1<<27)-1

vec = [(w,a) for w,a in zip(words,asm)] + extra
with open(os.path.join(HERE,'..','proj2_make','TOP','SIM','TESTBENCH','dec_vectors.vh'),'w') as f:
    f.write('// generated by TOOLS/gen_dec_vectors.py : encodings from GNU as, expected from python reference\n')
    for w,a in vec:
        d=ref(w); m = ILL_MASK if d['ill'] else FULL
        f.write(f'        chk_vec(32\'h{w:08x}, 27\'h{pack(d):07x}, 27\'h{m:07x}, "{a}");\n')
print(len(vec), 'vectors')
