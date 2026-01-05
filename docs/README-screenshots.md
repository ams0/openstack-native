# Adding Screenshots to Documentation

## Save Your Screenshot

Please save your Horizon dashboard screenshot to:

```
/home/opn/openstack-native/docs/images/horizon-compute-overview.png
```

## How to Save

### Option 1: Using SCP (from your local machine)
```bash
scp /path/to/screenshot.png opn@135.225.79.203:/home/opn/openstack-native/docs/images/horizon-compute-overview.png
```

### Option 2: Using drag-and-drop in VS Code
1. Open VS Code Remote SSH connection
2. Navigate to `/home/opn/openstack-native/docs/images/`
3. Drag and drop your screenshot
4. Rename to `horizon-compute-overview.png`

### Option 3: Upload via Azure Portal
1. Use Azure Cloud Shell or VM console
2. Upload the file
3. Move to the images directory

## Verify

After saving, verify the file exists:

```bash
ls -lh /home/opn/openstack-native/docs/images/horizon-compute-overview.png
```

## View Documentation

The screenshot is referenced in:
- `/home/opn/openstack-native/docs/horizon-access.md`
- `/home/opn/openstack-native/docs/horizon-screenshots.md`

If using a Markdown viewer, the image will be displayed inline.
