import Foundation
import DCloudUniappRuntime
import DCloudUTSFoundation
import DCloudUTSExtAPI

/// HBuilderX 5.26 app-ios export omits these classes from utssdk/interface.uts.
@objc(UTSSDKModulesDCloudUniModalShowModalResult)
@objcMembers
public class ShowModalResult: NSObject, ShowModalSuccess {
    public var errMsg: String
    public var content: String?
    public var cancel: Bool
    public var confirm: Bool

    public init(_ errMsg: String = "showModal:ok", _ cancel: Bool = false, _ confirm: Bool = false, _ content: String? = nil) {
        self.errMsg = errMsg
        self.cancel = cancel
        self.confirm = confirm
        self.content = content
    }
}

@objc(UTSSDKModulesDCloudUniModalHideModalResult)
@objcMembers
public class HideModalResult: NSObject, HideModalSuccess {
    public var errMsg: String

    public init(_ errMsg: String = "hideModal:ok") {
        self.errMsg = errMsg
    }
}
