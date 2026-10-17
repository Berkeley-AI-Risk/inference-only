"""Check basic routed timing, route completion and DRC error status.

Not a replacement for CDC/reset review, vendor image validation or board tests.
"""
import argparse
import json
from pathlib import Path
import re


def check(directory):
    timing = (directory/'timing-summary.rpt').read_text()
    route = (directory/'route-status.rpt').read_text()
    drc = (directory/'drc.rpt').read_text()
    section = timing.split('| Design Timing Summary', 1)
    if len(section) != 2:
        raise ValueError('Missing timing summary')
    rows = re.findall(r'^\s*(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+(\d+)\s+(\d+)\s+'
                      r'(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+(\d+)\s+(\d+)\s+'
                      r'(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+(\d+)\s+(\d+)\s*$',
                      section[1].split('| Clock Summary', 1)[0], re.MULTILINE)
    if len(rows) != 1:
        raise ValueError('Ambiguous timing summary')
    values = list(map(float, rows[0]))
    if (any(values[i] < 0 for i in (0, 4, 8)) or any(values[i] != 0 for i in (1, 2, 5, 6, 9, 10))
            or not all(values[i] > 0 for i in (3, 7, 11))
            or 'All user specified timing constraints are met.' not in timing):
        raise ValueError('Failing or incomplete timing')
    def count(label):
        matches = re.findall(re.escape(label)+r'\.+\s*:\s*(\d+)\s*:', route)
        if len(matches) != 1:
            raise ValueError('Missing/ambiguous route count: '+label)
        return int(matches[0])
    routable = count('# of routable nets')
    if routable < 1 or count('# of fully routed nets') != routable or count('# of nets with routing errors'):
        raise ValueError('Incomplete or failing route')
    if 'Report DRC' not in drc or re.search(r'\|\s*(?:Error|Critical Warning)\s*\|', drc, re.I):
        raise ValueError('Missing DRC report or unresolved severe DRC')
    return dict(passed=True, setup_slack_ns=values[0], hold_slack_ns=values[4],
                pulse_width_slack_ns=values[8], routed_nets=routable,
                scope='Basic reports only; not whole-machine, CDC/reset, physical security or production signoff.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    print(json.dumps(check(parser.parse_args().directory), indent=2))
