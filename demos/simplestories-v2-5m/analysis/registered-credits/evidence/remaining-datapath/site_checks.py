"""One-step credits on real local FF/enable cones. No arithmetic result proof is assumed."""
import json

def step_audit(prior,m,wd,regs,observed,body,checks):
    if "reset_n" not in m["netnames"]:
        m["netnames"]["reset_n"]=m["netnames"]["rst_n"]
    nonreset=set()
    for k in regs:
        b=prior.net(m,k)
        cells=[c for c in m["cells"].values() if c["connections"].get("Q")==b]
        assert len(cells)==1
        if cells[0]["type"] in ("$dffe","$dff"):
            nonreset.add(k)
    adff=prior.clocked
    def ff(module,k):
        if k not in nonreset:
            return adff(module,k)
        b=prior.net(module,k)
        (c,)=[c for c in module["cells"].values() if c["connections"].get("Q")==b]
        assert c["connections"]["CLK"]==prior.net(m,"clk")
        assert int(c["parameters"]["CLK_POLARITY"],2)==1
        if "EN_POLARITY" in c["parameters"]: assert int(c["parameters"]["EN_POLARITY"],2)==1
        return c["connections"]
    prior.clocked=ff
    try:
        cone,inputs,outputs=prior.make_comb(m,regs,observed)
    finally:
        prior.clocked=adff
    (wd/"local-cone.json").write_text(json.dumps({"modules":{"cone":cone}}))
    ports=[f"input [{len(b)-1}:0] {k}" for k,b in inputs.items()]
    ports+=["input h1,h2"]+["output "+k for k in checks]
    lines=["module audit("+",".join(ports)+");"]
    lines+=[f"wire [{len(b)-1}:0] {k};" for k,b in outputs.items()]
    lines+=["cone native("+",".join(f".{k}({k})" for k in list(inputs)+list(outputs))+");"]
    for k in regs:
        n=f"({k}_en ? {k}_d : {k})"
        if k not in nonreset: n=f"(reset_n ? {n} : 0)"
        lines+=[f"wire [{len(inputs[k])-1}:0] n_{k}={n};"]
    (wd/"step.sv").write_text("\n".join(lines+[body,"endmodule"]))
    prep="read_json local-cone.json; read_verilog -sv step.sv; hierarchy -top audit; flatten; opt; "
    for k,positive in checks.items():
        log=prior.yosys(prep+"sat "+("-verify" if positive else "-falsify")+f" -prove {k} 0 audit",wd)
        assert ("no model found: SUCCESS!" if positive else "model found: FAIL!") in log
    return checks

def lookup_ff(m,name):
    b=m["netnames"][name]["bits"]
    (ff,)=[v for v in m["cells"].values() if v["connections"].get("Q")==b]
    return ff

def postscale(prior,m,wd,mutant=False):
    e=m[prior.ENGINE]
    net=lambda n:prior.net(e,n)
    for i in range(4):
        e["netnames"][f"row{i}"]=e["netnames"][f"row_pipe_q[{i}]"]
    for which in ("low","high"):
        cell=e["cells"]["u_scale_"+which]
        pins=cell["connections"]
        assert cell["type"]=="board1_projection_postscale_mul"
        assert pins["a_i"]==net(which+"_operand_q") and pins["b_i"]==net("scale_operand_q")
        assert (len(pins["a_i"]),len(pins["b_i"]),len(pins["product_o"]))==(27,18,48)
        ff=lookup_ff(e,which+"_product_q")
        assert ff["type"]=="$dffe" and ff["connections"]["CLK"]==net("clk") and ff["connections"]["D"]==pins["product_o"]
        e["netnames"][which+"_capture"]={"bits":ff["connections"]["EN"],"attributes":{},"hide_name":0}
    q=lookup_ff(e,"result_q")
    assert len(q["connections"]["Q"])==50 and q["connections"]["CLK"]==net("clk")
    (adder,)=[c for c in e["cells"].values() if c["connections"].get("Y")==q["connections"]["D"]]
    assert adder["type"]=="$add" and adder["connections"]["A"]==net("low_product_q")+["0"]*2
    assert adder["connections"]["B"]==["0"]*25+net("high_product_q")[:25]
    assert net("low_operand_q")[25:]==net("scale_operand_q")[16:]==["0","0"]
    high_d=lookup_ff(e,"high_operand_q")["connections"]["D"]
    assert high_d[10:]==[high_d[9]]*17
    low_ff=next(c for c in e["cells"].values() if c["connections"].get("Q")==net("low_operand_q")[:25])
    dot=low_ff["connections"]["D"]+high_d[:10]
    assert len(dot)==35 and any(c["connections"].get("Y")==dot for c in e["cells"].values())
    e["netnames"]["merge_capture"]={"bits":q["connections"]["EN"],"attributes":{},"hide_name":0}
    regs=prior.REGS+["issue_count_q","scale_valid_q"]+[f"row{i}" for i in range(4)]
    obs=["weight_fire","metadata_fire","start_fire","issue","advance","low_capture","high_capture","merge_capture"]
    def invariant(p,h1,h2):
        s,l,c,col,meta,i,v=[p+x for x in ["state_q","valid_lanes_q","columns_q","column_q","metadata_count_q","issue_count_q","scale_valid_q"]]
        terms=[f"{l}<=64",f"({s}!=1 && {s}!=2 || (({c}==682 && {l}==64) || ({c}==256 && ({l}==42 || {l}==51 || {l}==64))))",
               f"({s}!=1 || ({meta}<{l} && {col}==0))",f"({s}!=2 || {col}<{c})",
               f"({s}<1 || {s}>3 || {i}==0)",f"({s}!=4 || {i}<={l})",f"({v}==0 || {s}==4)",
               f"({v}==0 || !{h1})",f"({v}[3:1]==0 || !{h2})"]
        for lane in range(4):
            pieces=[f"(32'd0+{p}row{lane})","32'd1"]+[f"{v}[{j}]" for j in range(lane)]
            terms.append(f"(!{v}[{lane}] || ({'+'.join(pieces)})=={i})")
        return " && ".join(terms)
    def pools(p):
        s,n,c,i,l=[p+x for x in ("state_q","metadata_count_q","column_q","issue_count_q","valid_lanes_q")]
        rem=f"(32'd0+{l}-{i})"
        w=f"({s}==2 ? ({c}>256 ? 32'd256 : {c}) : ({s}==3 ? 32'd256 : ({s}==4 ? 4*{rem} : 0)))"
        m=f"({s}==1 ? {n} : (({s}==2 || {s}==3) ? {l} : ({s}==4 ? {rem} : 0)))"
        return w,m
    w,mc=pools("");wn,mn=pools("n_")
    body=f"""
    wire spend=start_fire || metadata_fire || weight_fire;
    wire inv={invariant('','h1','h2')};
    wire n_inv={invariant('n_','spend','h1')};
    wire [31:0] w={w},wn={wn},m={mc},mn={mn};
    assign induction_error=inv && !n_inv;
    assign enable_error=(low_capture != (advance && scale_valid_q[1])) ||
        (high_capture != low_capture) || (merge_capture != (advance && scale_valid_q[2]));
    assign overlap=inv && (low_capture || merge_capture) && (spend || h1 || h2);
    assign budget_w=inv && 4*issue+wn>w+weight_fire;
    assign budget_m=inv && issue+mn>m+metadata_fire;
    assign cap=inv && (w>256 || m>64);
    assign competing=inv && ((issue && (weight_fire || metadata_fire)) || (weight_fire && metadata_fire));
    wire [3:0] qp=4'd0+scale_valid_q[0]+scale_valid_q[1];
    wire [3:0] qm=qp+scale_valid_q[2];
    wire [3:0] nqp=4'd0+n_scale_valid_q[0]+n_scale_valid_q[1];
    wire [3:0] nqm=nqp+n_scale_valid_q[2];
    assign duplicate_partial=inv && low_capture+nqp>issue+qp;
    assign duplicate_merge=inv && merge_capture+nqm>issue+qm;
    assign cover_post=inv && low_capture && merge_capture;
    assign wrong_factor=inv && 5*issue+wn>w+weight_fire;
    assign bad_same_row=inv && scale_valid_q[1] && scale_valid_q[2] && row1!=row2;
    """
    checks={k:True for k in ["induction_error","enable_error","overlap","budget_w","budget_m","cap","competing","duplicate_partial","duplicate_merge"]}
    checks.update(cover_post=False,wrong_factor=False,bad_same_row=False)
    if mutant:
        checks["enable_error"]=False
        checks={k:v for k,v in checks.items() if k=="enable_error"}
        body="\n".join(s for s in body.splitlines() if not s.strip().startswith("assign ") or "enable_error" in s)
    return step_audit(prior,e,wd,regs,obs,body,checks)

def service(prior,m,wd,key):
    if key=="rms":
        body="""
        wire sq=state_q==3, wt=state_q==11, sc=state_q==12;
        wire mus=sq||wt||sc;
        wire [7:0] mul_p=(state_q==11 ? 2 : (sq||sc||state_q==10 ? 1 : 0));
        wire [7:0] n_mul_p=(n_state_q==11 ? 2 : (n_state_q==3||n_state_q==12||n_state_q==10 ? 1 : 0));
        wire [7:0] ops_p=sq,n_ops_p=n_state_q==3;
        assign mul_bad=2*mus+n_mul_p>1+mul_p;
        assign ops_bad=mus+sq+n_ops_p>1+ops_p;
        assign too_tight=wt && mus && n_state_q==12;
        assign cover_square=sq && n_state_q==2;
        assign operand_error=(sq && (dsp_mode!=3 || dsp_activation!=vector_read_q ||
                                      dsp_dynamic_operand!=vector_read_q)) ||
            (wt && (dsp_mode!=0 || dsp_activation!=rms_normalized_q)) ||
            (sc && (dsp_mode!=4 || dsp_wide_operand!=weight_product_q || dsp_scale_operand!=rom_multiplier)) ||
            (!mus && (dsp_mode!=0 || dsp_activation!=0));
        assign cover_nonzero_square=sq && dsp_activation!=0;
        """
        checks={"mul_bad":True,"ops_bad":True,"too_tight":False,"cover_square":False,
                "operand_error":True,"cover_nonzero_square":False}
        observed="dsp_mode dsp_activation dsp_dynamic_operand vector_read_q rms_normalized_q dsp_wide_operand weight_product_q dsp_scale_operand rom_multiplier".split()
        assert m["cells"]["u_sealed_shared_multiply"]["connections"]["direct_weight_i"]==prior.net(m,"rom_coefficient")
    else:
        def pp(s):
            return f"({s}==1 ? 4 : ({s}==2 ? 3 : ({s}==3 ? 2 : (({s}==4 || {s}==7) ? 1 : 0))))"
        def op(s):
            return f"({s}>=1 && {s}<=4 ? 5+{s} : 0)"
        body=f"""
        wire mu=(state_q>=1 && state_q<=4) || state_q==7;
        wire [7:0] p={pp('state_q')},np={pp('n_state_q')};
        wire [7:0] q={op('state_q')},nq={op('n_state_q')};
        assign mul_bad=5*mu+np>4+p;
        assign ops_bad=5*(mu+2*(state_q==4))+nq>6+q;
        assign forced_gap_wrong=state_q==2 && n_state_q==3;
        assign cover_last=state_q==4 && n_state_q==11;
        assign operand_error=(state_q==1 && (dsp_first!=first_q || dsp_second!=cosine_q)) ||
            (state_q==2 && (dsp_first!=second_q || dsp_second!=sine_q)) ||
            (state_q==3 && (dsp_first!=second_q || dsp_second!=cosine_q)) ||
            (state_q==4 && (dsp_first!=first_q || dsp_second!=sine_q)) ||
            (state_q==7 && (dsp_first!=silu_value_q || dsp_second!=second_q)) ||
            (!mu && (dsp_first!=0 || dsp_second!=0));
        assign cover_nonzero_product=state_q==4 && dsp_first!=0 && dsp_second!=0;
        """
        checks={"mul_bad":True,"ops_bad":True,"forced_gap_wrong":False,"cover_last":False,
                "operand_error":True,"cover_nonzero_product":False}
        observed="dsp_first dsp_second first_q second_q cosine_q sine_q silu_value_q".split()
    return step_audit(prior,m,wd,["state_q"],observed,body,checks)
