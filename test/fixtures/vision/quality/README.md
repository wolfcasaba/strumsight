# E05-R09 synthetic grayscale fixtures

The domain tests generate every fixture in-memory. No camera image, identity,
or personal data is checked in.

- **dark:** an 8×8 low-luminance checkerboard (10/30)
- **clipped:** an 8×8 highlight-clipped checkerboard (230/255)
- **blurred:** 8×8 and 16×12 one-step gradients with low adjacent-pixel
  contrast, covering two resolutions
- **sharp/stable:** an 8×8 checkerboard (80/180), assessed twice unchanged
- **partial ROI:** a centered normalized 10%×10% rectangle

The implementation is also exercised through a 640×480 generated benchmark in
the round handoff. Threshold boundary cells are numeric test inputs, not
hand-estimated fixture pixels.
