import codecs

path = r'd:\桌面\Senior High School Grade 6\Role-playing system based on RAG_new\frontend\src\App.jsx'

with codecs.open(path, 'r', 'utf-8') as f:
    lines = f.read().split('\n')

line = lines[402]

# 1. Replace search button with copy-all button
old_btn = 'onClick={()=>setShowSearch(v=>!v)}><Icon name="search" />搜索</button>'
new_btn = 'onClick={copyAllMessages}><Icon name="copy" />复制全部</button>'
line = line.replace(old_btn, new_btn)

# 2. Remove search overlay
overlay_start = line.find('{showSearch &&')
chat_body_pos = line.find('<section className="chat-body"')
if overlay_start != -1 and chat_body_pos != -1:
    line = line[:overlay_start] + line[chat_body_pos:]

lines[402] = line

with codecs.open(path, 'w', 'utf-8') as f:
    f.write('\n'.join(lines))

print('Done.')
print('copyAllMessages in line:', 'copyAllMessages' in line)
print('showSearch removed:', '{showSearch' not in line)
