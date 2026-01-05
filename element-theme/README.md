# Element Theme Directory

This directory is used for custom branding and theming of the Element web interface.

## Logo

The setup script will automatically download the Samsesh logo here. You can replace it with your own:

- Place your logo as `logo.png` in this directory
- Recommended size: 256x256 pixels or larger
- Format: PNG with transparency

## Custom Themes

You can add custom CSS themes here. See the [Element Web theming documentation](https://github.com/vector-im/element-web/blob/develop/docs/theming.md) for more information.

## Usage

The `docker-compose.yaml` mounts this directory to `/app/themes/samsesh` in the Element container.
