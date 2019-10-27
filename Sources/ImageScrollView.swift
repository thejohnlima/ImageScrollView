//
//  ImageScrollView.swift
//  Beauty
//
//  Created by Nguyen Cong Huy on 1/19/16.
//  Copyright © 2016 Nguyen Cong Huy. All rights reserved.
//

import UIKit

@objc public protocol ImageScrollViewDelegate: UIScrollViewDelegate {
  func didTap(_ imageScrollView: ImageScrollView)
  func didChangeOrientation(_ imageScrollView: ImageScrollView)
}

open class ImageScrollView: UIScrollView {

  // MARK: - Constants
  static let zoomInFactorFromMinWhenDoubleTap: CGFloat = 2

  // MARK: - Properties
  private var pointToCenterAfterResize: CGPoint = .zero
  private var scaleToRestoreAfterResize: CGFloat = 1.0

  @objc public private(set) var zoomView: UIImageView? = nil
  @objc open var initialOffset: Offset = .begining
  @objc open var imageContentMode: ScaleMode = .widthFill
  @objc open weak var imageScrollViewDelegate: ImageScrollViewDelegate?

  public var tapGestureType: GestureType = .tap(.some(taps: 2))

  var imageSize: CGSize = .zero
  var maxScaleFromMinScale: CGFloat = 3.0

  // MARK: - Enums
  @objc public enum ScaleMode: Int {
    case aspectFill
    case aspectFit
    case widthFill
    case heightFill
  }

  @objc public enum Offset: Int {
    case begining
    case center
  }

  public enum GestureType {
    case tap(_ type: TapGestureType)

    public enum TapGestureType {
      case single
      case some(taps: Int)
    }
  }

  // MARK: - Initializers
  override public init(frame: CGRect) {
    super.init(frame: frame)
    initialize()
  }

  required public init?(coder aDecoder: NSCoder) {
    super.init(coder: aDecoder)
    initialize()
  }

  // MARK: - LifeCycle
  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  // MARK: - Overrides
  override open var frame: CGRect {
    willSet {
      if frame.equalTo(newValue) == false && newValue.equalTo(.zero) == false && imageSize.equalTo(.zero) == false {
        prepareToResize()
      }
    }

    didSet {
      if frame.equalTo(oldValue) == false && frame.equalTo(.zero) == false && imageSize.equalTo(.zero) == false {
        recoverFromResizing()
      }
    }
  }

  // MARK: - Private Methods
  private func initialize() {
    showsVerticalScrollIndicator = false
    showsHorizontalScrollIndicator = false
    bouncesZoom = true
    decelerationRate = .fast
    delegate = self

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(changeOrientationNotification),
      name: UIDevice.orientationDidChangeNotification,
      object: nil
    )
  }

  private func prepareToResize() {
    let boundsCenter = CGPoint(x: bounds.midX, y: bounds.midY)
    pointToCenterAfterResize = convert(boundsCenter, to: zoomView)

    scaleToRestoreAfterResize = zoomScale

    // If we're at the minimum zoom scale, preserve that by returning 0, which will be converted to the minimum
    // allowable scale when the scale is restored.
    if scaleToRestoreAfterResize <= minimumZoomScale + CGFloat(Float.ulpOfOne) {
      scaleToRestoreAfterResize = 0
    }
  }

  private func recoverFromResizing() {
    setMaxMinZoomScalesForCurrentBounds()

    // restore zoom scale, first making sure it is within the allowable range.
    let maxZoomScale = max(minimumZoomScale, scaleToRestoreAfterResize)
    zoomScale = min(maximumZoomScale, maxZoomScale)

    // restore center point, first making sure it is within the allowable range.

    // convert our desired center point back to our own coordinate space
    let boundsCenter = convert(pointToCenterAfterResize, to: zoomView)

    // calculate the content offset that would yield that center point
    var offset = CGPoint(x: boundsCenter.x - bounds.size.width/2.0, y: boundsCenter.y - bounds.size.height/2.0)

    // restore offset, adjusted to be within the allowable range
    let maxOffset = maximumContentOffset()
    let minOffset = minimumContentOffset()

    var realMaxOffset = min(maxOffset.x, offset.x)
    offset.x = max(minOffset.x, realMaxOffset)

    realMaxOffset = min(maxOffset.y, offset.y)
    offset.y = max(minOffset.y, realMaxOffset)

    contentOffset = offset
  }

  private func maximumContentOffset() -> CGPoint {
    return CGPoint(x: contentSize.width - bounds.width, y: contentSize.height - bounds.height)
  }

  private func minimumContentOffset() -> CGPoint {
    return .zero
  }

  private func configureImageForSize(_ size: CGSize) {
    imageSize = size
    contentSize = imageSize
    setMaxMinZoomScalesForCurrentBounds()
    zoomScale = minimumZoomScale

    switch initialOffset {
    case .begining:
      contentOffset =  CGPoint.zero
    case .center:
      let xOffset = contentSize.width < bounds.width ? 0 : (contentSize.width - bounds.width)/2
      let yOffset = contentSize.height < bounds.height ? 0 : (contentSize.height - bounds.height)/2

      switch imageContentMode {
      case .aspectFit:
        contentOffset =  CGPoint.zero
      case .aspectFill:
        contentOffset = CGPoint(x: xOffset, y: yOffset)
      case .heightFill:
        contentOffset = CGPoint(x: xOffset, y: 0)
      case .widthFill:
        contentOffset = CGPoint(x: 0, y: yOffset)
      }
    }
  }

  private func setMaxMinZoomScalesForCurrentBounds() {
    // calculate min/max zoomscale
    let xScale = bounds.width / imageSize.width // the scale needed to perfectly fit the image width-wise
    let yScale = bounds.height / imageSize.height // the scale needed to perfectly fit the image height-wise

    var minScale: CGFloat = 1

    switch imageContentMode {
    case .aspectFill:
      minScale = max(xScale, yScale)
    case .aspectFit:
      minScale = min(xScale, yScale)
    case .widthFill:
      minScale = xScale
    case .heightFill:
      minScale = yScale
    }

    let maxScale = maxScaleFromMinScale * minScale

    // don't let minScale exceed maxScale. (If the image is smaller than the screen, we don't want to force it to be zoomed.)
    if minScale > maxScale {
      minScale = maxScale
    }

    maximumZoomScale = maxScale
    minimumZoomScale = minScale * 0.999 // the multiply factor to prevent user cannot scroll page while they use this control in UIPageViewController
  }

  private func zoomRectForScale(_ scale: CGFloat, center: CGPoint) -> CGRect {
    var zoomRect = CGRect.zero

    // the zoom rect is in the content view's coordinates.
    // at a zoom scale of 1.0, it would be the size of the imageScrollView's bounds.
    // as the zoom scale decreases, so more content is visible, the size of the rect grows.
    zoomRect.size.height = frame.size.height / scale
    zoomRect.size.width  = frame.size.width  / scale

    // choose an origin so as to get the right center.
    zoomRect.origin.x    = center.x - (zoomRect.size.width  / 2.0)
    zoomRect.origin.y    = center.y - (zoomRect.size.height / 2.0)

    return zoomRect
  }

  private func addGesture(_ type: GestureType) {
    switch type {
    case .tap(let tap):
      var gesture = UITapGestureRecognizer(target: self, action: #selector(singleTapGestureRecognizer(_:)))
      if case .some(let taps) = tap {
        if taps == 2 {
          gesture = UITapGestureRecognizer(target: self, action: #selector(doubleTapGestureRecognizer(_:)))
          gesture.numberOfTapsRequired = taps
        }
      }
      zoomView?.addGestureRecognizer(gesture)
    }
  }

  @objc
  private func singleTapGestureRecognizer(_ gestureRecognizer: UIGestureRecognizer) {
    imageScrollViewDelegate?.didTap(self)
  }

  @objc
  private func doubleTapGestureRecognizer(_ gestureRecognizer: UIGestureRecognizer) {
    // zoom out if it bigger than middle scale point. Else, zoom in
    if zoomScale >= maximumZoomScale / 2.0 {
      setZoomScale(minimumZoomScale, animated: true)
    } else {
      let center = gestureRecognizer.location(in: gestureRecognizer.view)
      let zoomRect = zoomRectForScale(ImageScrollView.zoomInFactorFromMinWhenDoubleTap * minimumZoomScale, center: center)
      zoom(to: zoomRect, animated: true)
    }
    imageScrollViewDelegate?.didTap(self)
  }

  // MARK: - Public Methods
  open func setup() {
    var topSupperView = superview

    while topSupperView?.superview != nil {
      topSupperView = topSupperView?.superview
    }

    // Make sure views have already layout with precise frame
    topSupperView?.layoutIfNeeded()
  }

  open func refresh() {
    if let image = zoomView?.image {
      display(image: image)
    }
  }

  @objc
  public func adjustFrameToCenter() {
    guard let unwrappedZoomView = zoomView else { return }

    var frameToCenter = unwrappedZoomView.frame

    // center horizontally
    if frameToCenter.size.width < bounds.width {
      frameToCenter.origin.x = (bounds.width - frameToCenter.size.width) / 2
    } else {
      frameToCenter.origin.x = 0
    }

    // center vertically
    if frameToCenter.size.height < bounds.height {
      frameToCenter.origin.y = (bounds.height - frameToCenter.size.height) / 2
    } else {
      frameToCenter.origin.y = 0
    }

    unwrappedZoomView.frame = frameToCenter
  }

  @objc
  open func display(image: UIImage) {
    if let zoomView = zoomView {
      zoomView.removeFromSuperview()
    }

    zoomView = UIImageView(image: image)
    zoomView?.isUserInteractionEnabled = true
    addSubview(zoomView!)

    addGesture(tapGestureType)
    configureImageForSize(image.size)
  }

  @objc
  func changeOrientationNotification() {
    // A weird bug that frames are not update right after orientation changed. Need delay a little bit with async.
    DispatchQueue.main.async {
      self.configureImageForSize(self.imageSize)
      self.imageScrollViewDelegate?.didChangeOrientation(self)
    }
  }
}

// MARK: - UIScrollViewDelegate
extension ImageScrollView: UIScrollViewDelegate {
  public func scrollViewDidScroll(_ scrollView: UIScrollView) {
    imageScrollViewDelegate?.scrollViewDidScroll?(scrollView)
  }

  public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
    imageScrollViewDelegate?.scrollViewWillBeginDragging?(scrollView)
  }

  public func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
    imageScrollViewDelegate?.scrollViewWillEndDragging?(scrollView, withVelocity: velocity, targetContentOffset: targetContentOffset)
  }

  public func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
    imageScrollViewDelegate?.scrollViewDidEndDragging?(scrollView, willDecelerate: decelerate)
  }

  public func scrollViewWillBeginDecelerating(_ scrollView: UIScrollView) {
    imageScrollViewDelegate?.scrollViewWillBeginDecelerating?(scrollView)
  }

  public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
    imageScrollViewDelegate?.scrollViewDidEndDecelerating?(scrollView)
  }

  public func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
    imageScrollViewDelegate?.scrollViewDidEndScrollingAnimation?(scrollView)
  }

  public func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
    imageScrollViewDelegate?.scrollViewWillBeginZooming?(scrollView, with: view)
  }

  public func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
    imageScrollViewDelegate?.scrollViewDidEndZooming?(scrollView, with: view, atScale: scale)
  }

  public func scrollViewShouldScrollToTop(_ scrollView: UIScrollView) -> Bool {
    return false
  }

  @available(iOS 11.0, *)
  public func scrollViewDidChangeAdjustedContentInset(_ scrollView: UIScrollView) {
    imageScrollViewDelegate?.scrollViewDidChangeAdjustedContentInset?(scrollView)
  }

  public func viewForZooming(in scrollView: UIScrollView) -> UIView? {
    return zoomView
  }

  public func scrollViewDidZoom(_ scrollView: UIScrollView) {
    adjustFrameToCenter()
    imageScrollViewDelegate?.scrollViewDidZoom?(scrollView)
  }
}
