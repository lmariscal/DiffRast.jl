using DiffRast
using StaticArrays
using FileIO

vertex = SA_F32[
    -0.8; -0.8; 0.0; 1.0;;
     0.8; -0.8; 0.0; 1.0;;
    -0.8;  0.8; 0.0; 1.0;;;
]
attr = SA_F32[
    1.0; 0.0; 0.0;;
    0.0; 1.0; 0.0;;
    0.0; 0.0; 1.0;;;
]
index = UInt32[
    0; 1; 2;;
]

gl_ctx = DiffRast.create_context()
rast = DiffRast.rasterize(gl_ctx, vertex, index, width=256, height=256)
DiffRast.destroy_context(gl_ctx)

save("test_rast.png", DiffRast.data_to_image(rast))

