import figdraw
import merenda/nimkit/drawing/renderresources

proc prepareSnapshot*(
    manager: RenderResourceManager,
    renderer: FigRenderer[NoRendererBackendState],
    resources: RenderResourceSnapshot,
) =
  ## Compile the public snapshot API with just its direct imports.
  manager.prepare(renderer, resources)
