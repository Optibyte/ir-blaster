import os, json, shutil

history_dir = r'C:\Users\GOOD\AppData\Roaming\Code\User\History'
target_dir = r'd:\ir-blaster\lib'

empty_files = [os.path.join(r, f) for r, _, fs in os.walk(target_dir) for f in fs if f.endswith('.dart') and os.path.getsize(os.path.join(r, f)) == 0]
print('Empty files found:', len(empty_files))
for e in empty_files:
    print('-', e)

restored_count = 0

for d in os.listdir(history_dir):
    entry_json_path = os.path.join(history_dir, d, 'entries.json')
    if not os.path.exists(entry_json_path):
        continue
    
    try:
        with open(entry_json_path, 'r', encoding='utf-8') as f:
            data = json.load(f)
            
        res = data.get('resource', '')
        res_path = res.replace('file:///', '').replace('%3A', ':').replace('/', '\\')
        
        lower_empty_files = [e.lower() for e in empty_files]
        if res_path.lower() in lower_empty_files:
            entries = data.get('entries', [])
            entries.sort(key=lambda x: x.get('timestamp', 0), reverse=True)
            
            for ent in entries:
                f_path = os.path.join(history_dir, d, ent['id'])
                if os.path.exists(f_path) and os.path.getsize(f_path) > 0:
                    real_path = next(e for e in empty_files if e.lower() == res_path.lower())
                    shutil.copy(f_path, real_path)
                    empty_files.remove(real_path)
                    restored_count += 1
                    print('Restored:', real_path)
                    break
    except Exception as e:
        pass

print('Total Restored:', restored_count)
