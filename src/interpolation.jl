using ImageCore
using KernelAbstractions
using CUDA
using CUDAKernels
using StaticArrays

struct InterpolationParams
    numVertices
    numAttr
    numTriangles
    height
    width
    depth
end

function interpolate(
    attr::AbstractArray{Float32},
    rast::AbstractArray{Float32}, # The output from the rasterization module
    index::AbstractArray{UInt32}
)
    # @TODO: Add attr differentiable outputs
    channels, width, height = size(rast)

    out = zeros(Float32, size(attr, 1), width, height)
    if CUDA.functional()
        # @TODO: Abstract away the Array data type to avoid convertions
        rast_dev = CuArray(rast)
        index_dev = CuArray(index)
        attr_dev = CuArray(attr)

        out = CuArray(out)
        kernel = interpolate_kernel(CUDADevice(), 512)
        event = kernel(out, rast_dev, index_dev, attr_dev; ndrange=(width, height))
        wait(event)
        out = Array(out)
    else
        kernel = interpolate_kernel(CPU(), Threads.nthreads())
        event = kernel(out, rast, index, attr; ndrange=(width, height))
        wait(event)
    end
    data_to_image(out)
end

@kernel function interpolate_kernel(out, @Const(rast), @Const(indices), @Const(attr))
    P = @index(Global, NTuple)
    x, y = P
    idx = rast[4, x, y]

    @uniform numTriangles = size(indices, 2)
    @uniform numAttributes = size(attr, 2)

    if idx >= 1 && idx <= numTriangles
        bary = SVector{3, Float32}(rast[1, x, y], rast[2, x, y], 1.0 - rast[2, x, y] - rast[1, x, y])

        vertices = SVector{3, UInt32}(indices[1, Int(idx)], indices[2, Int(idx)], indices[3, Int(idx)])
        valid_idx = all(0 .<= vertices .< numAttributes)
        if valid_idx
            for a in 1:numAttributes
                current = SVector{3, Float32}(attr[1, a, 1], attr[2, a, 1], attr[3, a, 1])
                inter = bary'current
                out[a, x, y] = inter
            end
        end
    end
end
