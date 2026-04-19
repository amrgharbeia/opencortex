import re, glob

def check_file(fp):
    with open(fp, 'r') as f:
        content = f.read()
    blocks = re.findall(r'#\+begin_src lisp\s+(.*?)\s+#\+end_src', content, re.DOTALL)
    code = ' '.join(blocks)
    
    # Very simple check for unbalanced backquotes/commas
    # (Doesn't handle strings/comments perfectly but helps)
    backquotes = code.count('`')
    commas = code.count(',')
    
    # Count character literals
    bq_chars = code.count('#\\`')
    comma_chars = code.count('#\\,')
    
    real_commas = commas - comma_chars
    real_backquotes = backquotes - bq_chars
    
    if real_commas > 0 and real_backquotes == 0:
        print(f"WARN: {fp} has {real_commas} commas but 0 backquotes.")

for fp in glob.glob('skills/*.org'):
    check_file(fp)
