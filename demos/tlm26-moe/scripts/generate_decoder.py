"""Generate a static synthesizable controller for the pinned five-layer decoder.

Each generated control state has fixed wiring. There is no instruction port or
writable control store. Shared arithmetic and synchronous scratch memories are
explicit so the emitted design is usable by the Tang synthesis tools.
"""
if not __debug__:
    raise SystemExit('Assertion checks are required; run without -O or -OO. No verification performed.')
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
states={}
def state(label,body):
    if label in states: raise ValueError(label)
    states[label]=body
def goto(n): return 'state <= '+n+';'
def step(label,body,n): state(label,body+' '+goto(n))
def sequence(label,actions,end):
    for i,action in enumerate(actions):
        here=label if i==0 else label+'_'+str(i)
        nxt=end if i+1==len(actions) else label+'_'+str(i+1)
        action(here,nxt)
def setq(assign):
    return lambda here,nxt:step(here,assign,nxt)
def sr(address,dest):
    def act(here,nxt):
        step(here,'sadr <= '+address+';',here+'_FETCH')
        step(here+'_FETCH','',here+'_GOT')
        step(here+'_GOT',dest+' <= $signed(srdata);',nxt)
    return act
def sw(address,value):
    def act(here,nxt):
        step(here,'sadr <= '+address+'; swdata <= '+value+'; swe <= 1;',nxt)
    return act
def wr(address,dest):
    def act(here,nxt):
        step(here,'waddr <= '+address+'; wreq <= 1;',here+'_WAIT')
        state(here+'_WAIT','if(wfail) begin wreq<=0; '+goto('FAILED')+' end else if(wvalid) begin wreq<=0; '+dest+' <= $signed(wdata); '+goto(nxt)+' end')
    return act
def mul(a,b,dest,post='product'):
    def act(here,nxt):
        step(here,f'ma <= {a}; mb <= {b};',here+'_M')
        step(here+'_M','',here+'_GOT')
        step(here+'_GOT',dest+' <= '+post+';',nxt)
    return act
def call(op,setup=''):
    def act(here,nxt):
        step(here,setup+' back_'+op+' <= '+nxt+';',op)
    return act
def ret(op): return 'state <= back_'+op+';'
def div(a,b,dest):
    def act(here,nxt):
        step(here,'num <= '+a+'; den <= '+b+';',here+'_GO')
        step(here+'_GO','back_DIV <= '+here+'_DONE;', 'DIV')
        step(here+'_DONE',dest+' <= quo;',nxt)
    return act
def exp_lookup(x,dest):
    def act(here,nxt):
        step(here,'exaddr <= ('+x+' >= 1048576) ? 4096 : (('+x+' + 128) >>> 8);',here+'_L')
        step(here+'_L','',here+'_G')
        step(here+'_G',dest+' <= exp_q;',nxt)
    return act
def loop_end(here,index,limit,start,end):
    state(here,f'if({index}+1 >= {limit}) begin '+goto(end)+f' end else begin {index}<={index}+1; '+goto(start)+' end')
# Scratch vectors. Cache starts at word 2048, holds 5 * 256 * (32 K + 32 V).
V={'X':0,'Z':64,'Q':128,'K':192,'V':224,'H':256,'O':320,'G':384,'P':400,'U':592,'E':784,'Y':848,'S':912,'A':1168,'LGT':1424}
# Matrix dimensions and source/destination banks are fixed by the calling state.
state('IDLE','if(cmd_valid && cmd_ready) begin tok<=cmd_step ? next_token : cmd_token; is_step<=cmd_step; i<=0; layer<=0; lbase<=32832; '+goto('EMBED')+' end')
sequence('EMBED',[wr('{tok,6\'b0}+i','a'),sw('X+i','a <<< 1')],'EMBED_END')
loop_end('EMBED_END','i','64','EMBED','LAYER')
def matrix(key,offset,source,dest,rows,cols):
    return call('MAT',f'mbase <= {key}+{offset}; src <= {source}; dst <= {dest}; rows<={rows}; cols<={cols};')
def norm(base): return call('NORM',f'nbase <= {base};')
sequence('LAYER',[norm('lbase'), matrix('lbase',64,'Z','Q',64,64),matrix('lbase',4160,'Z','K',32,64),matrix('lbase',6208,'Z','V',32,64),
                  call('ROT','rbase<=Q; rlen<=64;'),call('ROT','rbase<=K; rlen<=32;'),setq('i<=0;')],'CACHE')
sequence('CACHE',[sr('K+i','a'),sw('cachebase+i','a'),sr('V+i','a'),sw('cachebase+32+i','a')],'CACHE_END')
loop_end('CACHE_END','i','32','CACHE','HEADSET')
step('HEADSET','head<=0;','HEAD')
step('HEAD','t<=0; maxv<=-64\'sh7fffffffffffffff;','SCORE')
step('SCORE','j<=0; accum<=0;','SCORE_DOT')
sequence('SCORE_DOT',[sr('Q+(head<<3)+j','a'),sr('2048+(layer<<14)+(t<<6)+((head>>1)<<3)+j','b'),mul('a','b','accum','accum+product')],'S_D_END')
loop_end('S_D_END','j','8','SCORE_DOT','SCORE_SCALE')
sequence('SCORE_SCALE',[mul('(accum+32768)>>>16',"32'sd11585",'a','(product+16384)>>>15'),sw('S+t','a'),setq('if(a>maxv) maxv<=a;')],'SCORE_END')
loop_end('SCORE_END','t','pos+1','SCORE','SOFT_START')
sequence('SOFT_START',[call('SOFT','softbase<=S; softlen<=pos+1;'),setq('j<=0;')],'HEAD_LANE')
step('HEAD_LANE','t<=0; accum<=0;','HEAD_VALUE')
sequence('HEAD_VALUE',[sr('S+t','a'),sr('2048+(layer<<14)+(t<<6)+32+((head>>1)<<3)+j','b'),mul('a','b','accum','accum+product')],'H_V_END')
loop_end('H_V_END','t','pos+1','HEAD_VALUE','HEAD_WRITE')
sequence('HEAD_WRITE',[sw('H+(head<<3)+j','(accum+32768)>>>16')],'H_J_END')
loop_end('H_J_END','j','8','HEAD_LANE','H_HEAD_END')
loop_end('H_HEAD_END','head','8','HEAD','POST_ATTN')
sequence('POST_ATTN',[matrix('lbase',8256,'H','O',64,64),call('ADD',''),norm('lbase+12352'),matrix('lbase',12416,'Z','G',8,64),
                      setq("top0<=0;top1<=0;best0<=-64'sh7fffffffffffffff;best1<=-64'sh7fffffffffffffff;i<=0;")],'ROUTE')
sequence('ROUTE',[sr('G+i','a'),setq('if(a>best0) begin best1<=best0;top1<=top0;best0<=a;top0<=i;end else if(a>best1) begin best1<=a;top1<=i;end')],'ROUTE_END')
loop_end('ROUTE_END','i','8','ROUTE','ROUTED')
sequence('ROUTED',[sw('A','best0'),sw('A+1','best1'),call('SOFT','softbase<=A;softlen<=2;maxv<=best0;'),setq('rank<=0;')],'EXPERT')
sequence('EXPERT',[setq('expertbase<=lbase+12928+(rank==0 ? top0 : top1)*36864;'),
                   matrix('expertbase',0,'Z','P',192,64),matrix('expertbase',12288,'Z','U',192,64),setq('i<=0;')],'ACT')
sequence('ACT',[sr('P+i','a'),exp_lookup('(a<0 ? -a : a)','b'),
                div('((a<0 ? b : 16777216) <<< 16)','16777216+b','c'),
                mul('a','c','d','(product+32768)>>>16'),sr('U+i','b'),
                mul('d','b','a','(product+32768)>>>16'),sw('P+i','a')],'ACT_END')
loop_end('ACT_END','i','192','ACT','EXPERT_OUT')
sequence('EXPERT_OUT',[matrix('expertbase',24576,'P','E',64,192),sr('A+rank','coeff'),setq('i<=0;')],'MIX')
# Retain first expert integer output. Combine weighted products once (single rounding).
state('MIX','if(!rank) '+goto('MIX_FIRST')+' else '+goto('MIX_SECOND'))
sequence('MIX_FIRST',[sr('E+i','a'),sw('Y+i','a')],'MIX_END')
sequence('MIX_SECOND',[sr('Y+i','a'),mul('a','coef0','accum'),sr('E+i','a'),mul('a','coeff','b','(product+accum+32768)>>>16'),sw('O+i','b')],'MIX_END')
loop_end('MIX_END','i','64','MIX','EXPERT_END')
state('EXPERT_END','if(rank==0) begin rank<=1;coef0<=coeff;'+goto('EXPERT')+' end else '+goto('ADD_FFN'))
sequence('ADD_FFN',[call('ADD')],'NEXT_LAYER')
state('NEXT_LAYER','if(layer==4) '+goto('OUTPUT')+' else begin layer<=layer+1;lbase<=lbase+307840;'+goto('LAYER')+' end')
sequence('OUTPUT',[norm('32768'),matrix("21'd0",0,'Z','LGT',512,64),setq("best0<=-64'sh7fffffffffffffff;i<=0;")],'ARGMAX')
sequence('ARGMAX',[sr('LGT+i','a'),setq('if(a>best0) begin best0<=a;winner<=i;end')],'ARG_END')
loop_end('ARG_END','i','512','ARGMAX','COMMIT')
step('COMMIT','pos<=pos+1;next_token<=winner;rep_valid<=1;rep_kind<=is_step?2:1;rep_token<=is_step?tok:0;','IDLE')
step('FAILED','rep_valid<=1;rep_kind<=3;rep_token<=0;','IDLE')
# Reusable constant-function engines.
step('MAT','r<=0; wi<=mbase;','MAT_ROW')
step('MAT_ROW','j<=0;accum<=0;','MAT_MAC')
sequence('MAT_MAC',[sr('src+j','a'),wr('wi','b'),mul('a','b','accum','accum+product'),setq('wi<=wi+1;')],'MAT_J')
loop_end('MAT_J','j','cols','MAT_MAC','MAT_WRITE')
sequence('MAT_WRITE',[sw('dst+r','(accum+16384)>>>15')],'MAT_R')
loop_end('MAT_R','r','rows','MAT_ROW','MAT_RET')
state('MAT_RET',ret('MAT'))
step('ADD','i<=0;','ADD_I')
sequence('ADD_I',[sr('X+i','a'),sr('O+i','b'),sw('X+i','a+b')],'ADD_END')
loop_end('ADD_END','i','64','ADD_I','ADD_RET')
state('ADD_RET',ret('ADD'))
step('NORM','i<=0; accum<=0;','NORM_SS')
sequence('NORM_SS',[sr('X+i','a'),mul('a','a','accum','accum+product')],'NORM_SS_END')
loop_end('NORM_SS_END','i','64','NORM_SS','SQRT_START')
step('SQRT_START',"rad<=(accum>>>6)+42950; root<=0; rems<=0; bitcount<=0;",'SQRT')
state('SQRT','rad<=rad<<2; rems<=sqrt_cand>=sqrt_trial ? sqrt_cand-sqrt_trial : sqrt_cand;root<=(root<<1)+(sqrt_cand>=sqrt_trial); if(bitcount==31) '+goto('NORM_SCALE')+' else bitcount<=bitcount+1;')
step('NORM_SCALE','i<=0;','NORM_I')
sequence('NORM_I',[sr('X+i','a'),wr('nbase+i','b'),mul('a','b','c','product<<<4'),div('c','root','a'),sw('Z+i','a')],'NORM_END')
loop_end('NORM_END','i','64','NORM_I','NORM_RET')
state('NORM_RET',ret('NORM'))
step('ROT','i<=0;','ROT_PAIR')
sequence('ROT_PAIR',[sr('rbase+i','a'),sr('rbase+i+1','b'),setq('rotaddr<=((pos<<2)+((i>>1)&3));'),setq(''),
                     mul('a','cosq','c'),mul('b','sinq','d','(c-product+16384)>>>15'),sw('rbase+i','d'),
                     mul('a','sinq','c'),mul('b','cosq','d','(c+product+16384)>>>15'),sw('rbase+i+1','d')],'ROT_END')
state('ROT_END','if(i+2>=rlen) '+ret('ROT')+' else begin i<=i+2;'+goto('ROT_PAIR')+' end')
step('SOFT','i<=0;esum<=0;','SOFT_I')
sequence('SOFT_I',[sr('softbase+i','a'),exp_lookup('(maxv-a)','b'),sw('softbase+i','b'),setq('esum<=esum+b;')],'SOFT_END_I')
loop_end('SOFT_END_I','i','softlen','SOFT_I','SOFT_SCALE')
step('SOFT_SCALE','i<=0;','SOFT_J')
sequence('SOFT_J',[sr('softbase+i','a'),div('a<<<16','esum','b'),sw('softbase+i','b')],'SOFT_END_J')
loop_end('SOFT_END_J','i','softlen','SOFT_J','SOFT_RET')
state('SOFT_RET',ret('SOFT'))
# Floor((num + den/2)/den) for positive den, matching Python signed floor division.
step('DIV','signednum<=num+$signed({1\'b0,den[62:1]});','DIV_GO')
step('DIV_GO',"neg<=signednum<0; dividend<=signednum<0 ? -signednum : signednum; drem<=0;quot<=0;bitcount<=0;",'DIV_BIT')
state('DIV_BIT','dividend<=dividend<<1;drem<=div_cand>=den ? div_cand-den : div_cand;quot<=(quot<<1)+(div_cand>=den); if(bitcount==63) '+goto('DIV_DONE')+' else bitcount<=bitcount+1;')
state('DIV_DONE','quo<=neg ? -$signed(quot)-(drem!=0) : $signed(quot);'+ret('DIV'))
body='''// Generated by scripts/generate_decoder.py. Fixed five-layer top-2-of-8 decoder.
module tlm_decoder(input wire clk, rst_n, clear_i, cmd_valid, cmd_step,
 input wire [8:0] cmd_token, output wire cmd_ready,
 output reg rep_valid, output reg [1:0] rep_kind, output reg [8:0] rep_token,
 output reg wreq, output reg [20:0] waddr, input wire wvalid,wfail, input wire signed [15:0] wdata);
'''
for n,v in V.items(): body+=f'localparam {n}={v};\n'
for c,label in enumerate(states): body+=f'localparam {label}=9\'d{c};\n'
assert len(states)<512
body+='''
reg [8:0] state,back_MAT,back_ADD,back_NORM,back_ROT,back_SOFT,back_DIV;
reg [8:0] tok,next_token,winner,pos;
reg is_step,rank;
reg [2:0] layer,top0,top1;
reg [3:0] head;
reg [9:0] i,j,r,t,rows,cols,rlen,softlen;
reg [10:0] src,dst,rbase,softbase;
reg [20:0] lbase,mbase,nbase,expertbase,wi;
reg signed [63:0] a,b,c,d,accum,best0,best1,maxv,coeff,coef0,esum;
reg signed [31:0] ma,mb; reg signed [63:0] product;
always @(posedge clk) product <= ma*mb;
reg [16:0] sadr; reg signed [31:0] srdata,swdata; reg swe;
reg signed [31:0] scratch[0:83967];
always @(posedge clk) begin if(swe) scratch[sadr]<=swdata;else srdata<=scratch[sadr];end
wire [16:0] cachebase=17'd2048+({14'd0,layer}<<14)+({8'd0,pos}<<6);
reg [12:0] exaddr; reg [9:0] rotaddr;
reg [31:0] exptable[0:4096];reg signed [31:0] costable[0:1023],sintable[0:1023];
reg [31:0] exp_q;reg signed [31:0] cosq,sinq;
initial begin $readmemh("exp.hex",exptable);$readmemh("cos.hex",costable);$readmemh("sin.hex",sintable);end
always @(posedge clk) begin exp_q<=exptable[exaddr];cosq<=costable[rotaddr];sinq<=sintable[rotaddr];end
reg [63:0] rad,rems,root,dividend,drem,quot;
reg [6:0] bitcount;
reg signed [63:0] num,den,signednum,quo; reg neg;
wire [63:0] div_cand=(drem<<1)+dividend[63];
wire [63:0] sqrt_cand=(rems<<2)+rad[63:62];
wire [63:0] sqrt_trial=(root<<2)+1;
assign cmd_ready=rst_n && !clear_i && state==IDLE && pos<256;
always @(posedge clk) begin
 swe<=0;rep_valid<=0;rep_kind<=0;rep_token<=0;
 if(!rst_n || clear_i) begin state<=IDLE;wreq<=0;pos<=0;next_token<=0; end
 else case(state)
'''
for n,code in states.items(): body+=f'    {n}: begin {code} end\n'
body+='    default: begin state<=FAILED;wreq<=0;end\n endcase\nend\nendmodule\n'
(ROOT/'rtl/tlm_decoder.sv').write_text(body)
print(len(states),'fixed states')
