""" Converts a .png image, made of tiles representing slices of a voxel, into a .vox model. """

import argparse
import struct
from PIL import Image

def parse_args():
    ''' Parse the command line arguments for the script. '''
    parser = argparse.ArgumentParser(description="Convert an image to Ken Silverman .VOX format")
    parser.add_argument('-i', '--input',  required=True, help="Input image file")
    parser.add_argument('-o', '--output', default=None, help="Output .vox file")
    parser.add_argument('-c', '--cols',   type=int, required=True, help="Number of columns (tiles)")
    parser.add_argument('-r', '--rows',   type=int, required=True, help="Number of rows (tiles)")
    parser.add_argument('-f', '--face', choices=['front', 'back', 'top', 'bottom', 'left', 'right'],
                    default='front', help="Which way should the model face (default: front)")

    return parser.parse_args()

def load_image(_file, _cols, _rows):
    ''' Load the image file and return the imgae object and tile dimensions. '''
    img = Image.open(_file).convert('RGBA')
    img_w, img_h = img.size

    tile_w, tile_h = img_w // _cols, img_h // _rows

    return img, tile_w, tile_h, _rows * _cols

def voxel_parse(_img, _w, _h, _rows, _cols):
    ''' Parse the image for voxel data (x,y,z,color)'''
    voxels, palette = [], []

    color_map = {}
    next_color_index = 0

    # Iterate through each tile in row-major order
    for row in range(_rows):
        for col in range(_cols):
            # Calculate the z-value for this tile
            z = (row * _cols) + col

            # Loop through each pixel within the current tile
            for y in range(_h):
                pixel_y = (row * _h) + y

                for x in range(_w):
                    pixel_x = (col * _w) + x

                    # Get the pixel data (RGBA)
                    r, g, b, a = _img.getpixel((pixel_x, pixel_y))

                    # If alpha is less than 255, treat it as a transparent voxel
                    if a < 255:
                        voxels.append({'x': x, 'y': y, 'z': z, 'color': 255})
                        continue

                    # Build the color map and palette
                    color = (r, g, b)
                    if color not in color_map:
                        if next_color_index < 255:
                            color_map[color] = next_color_index
                            palette.append(color)
                            next_color_index += 1
                        else:
                            raise ValueError("Palette exceeded 255 colors!")

                    # Add voxel data
                    voxels.append({'x': x, 'y': y, 'z': z, 'color': color_map[color]})

    return voxels, palette

def voxel_rotate(_vox_data, _face):
    ''' Reorganize the voxel data based on the desired face orientation. '''
    for voxel in _vox_data:
        x, y, z = voxel['x'], voxel['y'], voxel['z']

        if _face == 'front':
            voxel['x'], voxel['y'], voxel['z'] =  y,  z,  x
        elif _face == 'back':
            voxel['x'], voxel['y'], voxel['z'] =  y, -z, -x
        elif _face == 'top':
            voxel['x'], voxel['y'], voxel['z'] = -z, y,  x
        elif _face == 'bottom':
            voxel['x'], voxel['y'], voxel['z'] =  z, -y,  x
        elif _face == 'left':
            voxel['x'], voxel['y'], voxel['z'] =  y,  x, -z
        elif _face == 'right':
            voxel['x'], voxel['y'], voxel['z'] =  y, -x,  z
        else:
            raise ValueError(f"Unknown face orientation: {_face}")

    return _vox_data

def voxel_recanvas(_w, _h, _d, _face):
    ''' Adjust the voxel dimensions based on the face orientation. '''
    if _face in ['front', 'back']:
        return _h, _d, _w
    elif _face in ['top', 'bottom']:
        return _d, _h, _w
    elif _face in ['left', 'right']:
        return _h, _w, _d
    else:
        raise ValueError(f"Unknown face orientation: {_face}")

def voxel_flatten(_vox_data, _w, _h, _d):
    ''' Flatten the voxel data from structs to an array. '''
    _new_vox_data = [255] * (_w * _h * _d)

    for voxel in _vox_data:
        index = voxel['x'] + (voxel['y'] * _w) + (voxel['z'] * _w * _h)
        _new_vox_data[index] = voxel['color']

    return _new_vox_data

def write_vox_file(_file, _voxels, _pal, _w, _h, _d):
    ''' Write the voxel data to the new .vox file. '''
    with open(_file, 'wb') as f:
        f.write(struct.pack('l', _w))
        f.write(struct.pack('l', _h))
        f.write(struct.pack('l', _d))

        f.write(bytearray(_voxels))

        while len(_pal) < 256:
            _pal.append((0, 0, 0))

        for color in _pal:
            r, g, b = color
            f.write(struct.pack('BBB', r // 4, g // 4, b // 4))

if __name__ == "__main__":
    # parse arguments to image variables
    args = parse_args()
    img_i, img_o = args.input, args.output
    img_cols, img_rows = args.cols, args.rows
    vox_face = args.face

    # get voxel values from image
    vox_image, vox_w, vox_h, vox_d = load_image(img_i, img_cols,img_rows)
    vox_voxels, vox_pal = voxel_parse(vox_image, vox_w,vox_h, img_rows,img_cols)

    # rotate voxels (if needed)
    vox_voxels = voxel_rotate(vox_voxels, vox_face)
    print(vox_w, vox_h, vox_d)
    vox_w, vox_h, vox_d = voxel_recanvas(vox_w, vox_h, vox_d, vox_face)
    print(vox_w, vox_h, vox_d)

    # flatten voxel data
    vox_array = voxel_flatten(vox_voxels, vox_w,vox_h,vox_d)

    # write voxel data to .vox file
    img_o = img_o or img_i.replace('.png', '.vox')
    write_vox_file(img_o, vox_array, vox_pal, vox_w,vox_h,vox_d)
    print(f"VOX file written to {img_o}")
