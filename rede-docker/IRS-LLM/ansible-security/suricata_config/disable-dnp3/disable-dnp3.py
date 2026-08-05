def match(rule, filename):
    return ' dnp3 ' in rule['raw'] or rule['raw'].startswith('alert dnp3')

def filter(rule, filename):
    return None
