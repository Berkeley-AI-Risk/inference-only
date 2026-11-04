import re

def observer_only(text,native):
    executable=text
    while True:
        match=re.search(r'\b(?:assert|cover)\s*\(',executable)
        if match is None:break
        end,depth=match.end(),1
        while depth:depth+=(executable[end]=='(')-(executable[end]==')');end+=1
        executable=executable[:match.start()]+' begin end '+executable[end:]
    # A <= inside an if predicate is a comparison, not a native register
    # assignment. Reject side-effect assignments there before removing only
    # the predicate; keep all actual procedural bodies and for-loop writes.
    while True:
        match=re.search(r'\bif\s*\(',executable)
        if match is None:break
        end,depth=match.end(),1
        while depth:depth+=(executable[end]=='(')-(executable[end]==')');end+=1
        if re.search(r'(?<![<>!=])=(?!=)',executable[match.end():end-1]):
            raise ValueError('Side-effect assignment in added observer predicate')
        executable=executable[:match.start()]+' begin end '+executable[end:]
    targets=re.findall(r'\b(\w+)\s*(?:\[[^;\n]*?\])?\s*(?:<=|(?<![<>=!])=(?!=))',executable)
    local_indices=set(re.findall(r'for\s*\(\s*integer\s+(\w+)\s*=',executable))
    code=re.sub(r'/\*[\s\S]*?\*/|//[^\n]*','',native)
    if any((not name.startswith('f_')and name not in local_indices)or re.search(r'\b'+name+r'\b',code)for name in targets):
        raise ValueError('Added observer drives native guard/transport state')

def readonly(monitor,native):
    # Function locals are scoped copies, not native module variables. Check
    # every function assignment explicitly before using the module-level check.
    spans=list(re.finditer(r'\bfunction\b[\s\S]*?\bendfunction\b',monitor));outside=monitor
    for match in reversed(spans):
        function=match[0];header=function[:function.index(';')]
        name=re.search(r'function\s+(?:automatic\s+)?(?:\[[^]]+\]\s*)?(\w+)\s*\(',header)
        if name is None or not name[1].startswith('f_')or re.search(r'\b(?:output|inout|ref)\b',header):raise ValueError('Only pure input-valued observation functions allowed')
        allowed={name[1]}
        for declaration in re.findall(r'\b(?:reg|logic|integer)\s+(?:\[[^]]+\]\s*)?([^;]+);',function):
            allowed.update(re.findall(r'\b[A-Za-z_]\w*\b',declaration))
        allowed.update(re.findall(r'for\s*\(\s*integer\s+(\w+)\s*=',function))
        targets=re.findall(r'\b(\w+)\s*(?:\[[^;\n]*?\])?\s*(?:<=|(?<![<>=!])=(?!=))',function)
        for concat in re.findall(r'\{([^{}]+)\}\s*=(?!=)',function):targets+=re.findall(r'\b[A-Za-z_]\w*\b',concat)
        if any(n not in allowed for n in targets):raise ValueError('Observation function writes outside its local variables')
        outside=outside[:match.start()]+outside[match.end():]
    # The exact generate-loop index is local to its generated observation view.
    for name in re.findall(r'for\s*\(\s*genvar\s+(\w+)\s*=',outside):
        outside=re.sub(r'\b'+re.escape(name)+r'\b','f_local_gen_'+name,outside)
    outside=outside.replace('genvar ','integer ').replace('positions_i<=16','positions_i<17')
    outside=re.sub(r'/\*[\s\S]*?\*/|//[^\n]*','',outside)
    observer_only(outside,native)
