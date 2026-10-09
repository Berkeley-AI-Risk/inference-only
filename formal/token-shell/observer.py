def observer_cone(module):
    """Conservative bit dependency closure, including sequential cells.

    A memory read address influences only that read port, not other read ports
    or stored data. Write controls/data conservatively influence ALL reads.
    All other cell inputs conservatively influence all of their outputs.
    """
    def bits(values): return {bit for bit in values if isinstance(bit, int)}
    cells, nets = module['cells'], module['netnames']
    selector = bits(nets['f_tape_slot']['bits'])
    constants = [cell for cell in cells.values() if cell['type'] == '$anyconst']
    assert len(constants) == 1 and int(constants[0]['parameters']['WIDTH'], 2) == 12
    assert bits(constants[0]['connections']['Y']) == selector and len(selector) == 12
    edges = []
    memory_sinks = set()
    for name, cell in cells.items():
        ports, directions = cell['connections'], cell['port_directions']
        if cell['type'] == '$mem_v2':
            params = cell['parameters']
            width, abits, reads = (int(params[key], 2) for key in ('WIDTH', 'ABITS', 'RD_PORTS'))
            write_bits = set().union(*(bits(value) for port, value in ports.items() if port.startswith('WR_')))
            memory_sinks |= write_bits
            edges.append((name + ':all-writes', write_bits, bits(ports['RD_DATA'])))
            for index in range(reads):
                address = bits(ports['RD_ADDR'][abits*index:abits*(index+1)])
                inputs = address | set().union(*(bits([ports[port][index]])
                    for port in ('RD_CLK', 'RD_EN', 'RD_ARST', 'RD_SRST')))
                outputs = bits(ports['RD_DATA'][width*index:width*(index+1)])
                edges.append((name + ':read-' + str(index), inputs, outputs))
                if name == 'token_tape_q' and address == selector:
                    assert outputs == bits(nets['f_slot_observed']['bits'])
                else:
                    memory_sinks |= inputs
        else:
            inputs = set().union(*(bits(value) for port, value in ports.items() if directions[port] == 'input'))
            outputs = set().union(*(bits(value) for port, value in ports.items() if directions[port] == 'output'))
            edges.append((name, inputs, outputs))
    reached = set(selector)
    while True:
        new = set().union(*(outputs for _, inputs, outputs in edges if reached & inputs))
        if new <= reached: break
        reached |= new
    protected = {name: bits(row['bits']) for name, row in nets.items()
                 if not row['hide_name'] and not name.startswith('f_')}
    protected.update({name: bits(row['bits']) for name, row in module['ports'].items()})
    hits = [name for name, value in protected.items() if reached & value]
    assert not hits, hits
    assert not (reached & memory_sinks), 'Observer influences production memory control or write data.'
    return {'selector_bits': sorted(selector), 'reached_bits': sorted(reached),
            'complete_reached_edges': [{'cell_or_memory_port': name,
                'reached_inputs': sorted(inputs & reached), 'outputs': sorted(outputs)}
                for name, inputs, outputs in edges if inputs & reached],
            'reached_visible_nets': [name for name, row in nets.items()
                if not row['hide_name'] and bits(row['bits']) & reached],
            'production_named_net_or_port_hits': hits, 'production_memory_sink_hits': [],
            'memory_rule': 'Per-read-port address/control dependence; all writes conservatively affect all read outputs.'}

