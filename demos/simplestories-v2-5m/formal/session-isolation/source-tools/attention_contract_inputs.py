"""Enumerate every native attention child input and its relevant admission.

These are observation conditions, never input assumptions. The two-copy parent
must prove equality at each condition. No clock/reset or data input is silently
omitted; generated MAC lanes are expanded at their actual eight-lane geometry.
"""
import re

from run_service_relational import port_connections, width


def observe(raw, definitions, parser):
    taps = {}
    obligations = []
    instances = {}
    for match in re.finditer(r'^\s+(board1_\w+)\s+(?:#\([^\n]*\)\s+)?(u_\w+)\s*\(', raw, re.M):
        module, instance = match[1], match[2]
        cursor = match.end()
        end, level = cursor, 1
        while level:
            level += (raw[end] == '(') - (raw[end] == ')')
            end += 1
        connections = port_connections(raw[cursor:end-1])
        ports = parser.ports(definitions[module])
        if set(connections) != set(ports):
            raise ValueError('Incomplete actual child port inventory: ' + instance)
        entries = {}
        for port, (direction, shape) in ports.items():
            if direction != 'input':
                continue
            expression = connections[port]
            if port in ('clk', 'rst_n', 'reset_n'):
                if expression != ('clk' if port == 'clk' else 'rst_n'):
                    raise ValueError('Unexpected child clock/reset connection')
                entries[port] = dict(expression=expression, kind='common_clock_or_reset')
                continue
            guard = '1'
            if instance in ('u_score_lane', 'u_value_lane'):
                guard = 'interface_live && state_q==' + ('33' if instance == 'u_score_lane' else '24')
            elif instance.endswith('_bram'):
                if port == 'read_address_i':
                    guard = connections['read_enable_i']
                elif port in ('write_address_i', 'write_data_i') or port.endswith('_write_data_i'):
                    guard = connections['write_enable_i']
            elif instance == 'u_norm_stage' and port in ('value_i', 'source_exponent_i'):
                guard = 'interface_live && (' + connections['capture_i'] + ')'
            elif instance == 'u_value_prefix':
                if port in ('coordinate_i', 'value_i'):
                    guard = connections['stage_value_valid_i']
                elif port == 'exponent_i':
                    guard = '(' + connections['stage_begin_i'] + ') || (' + connections['stage_value_valid_i'] + ')'
            elif instance in ('u_align8', 'u_shift', 'u_divider', 'u_exp_lut'):
                control = port.endswith(('_valid_i', '_ready_i')) or port in ('clear_i', 'cancel_i')
                if not control:
                    guard = '(' + connections['request_valid_i'] + ') && !clear_i'
                    if instance != 'u_exp_lut':
                        guard += ' && state_q!=ST_FAULT'
            elif instance not in ('u_norm_stage',):
                raise ValueError('Unreviewed native child contract: ' + instance)
            bits = width(shape)
            generated = instance in ('u_score_lane', 'u_value_lane')
            if generated:
                expression = '{' + ','.join(re.sub(r'\bmac\b', str(i), expression) for i in reversed(range(8))) + '}'
                bits *= 8
            name = 'contract_' + instance + '_' + port
            guard_name = name + '_when'
            taps[name] = (bits, expression)
            taps[guard_name] = (1, guard)
            obligations.append('            assert(a_' + guard_name + '==b_' + guard_name + ');')
            obligations.append('            if(a_' + guard_name + ')assert(a_' + name + '==b_' + name + ');')
            entries[port] = dict(expression=connections[port], observed_expression=expression,
                                 width=bits, kind='proved_admission_equality', guard=guard,
                                 data_tap=name, guard_tap=guard_name)
        instances[instance] = dict(module=module, inputs=entries,
                                   generated_instances=8 if generated else 1)
    if len(instances) != 12 or sum(x['generated_instances'] for x in instances.values()) != 26:
        raise ValueError('Actual attention child geometry changed')
    return taps, obligations, instances
