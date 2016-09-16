//
//  AppDelegate.swift
//  iPoliTO2
//
//  Created by Carlo Rapisarda on 30/07/2016.
//  Copyright © 2016 crapisarda. All rights reserved.
//

import UIKit

enum ControllerIndex: Int {
    case home = 0
    case subjects = 1
    case career = 2
    case map = 3
}

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate, UITabBarControllerDelegate, PTSessionDelegate {

    var window: UIWindow?
    var session: PTSession? {
        return PTSession.shared
    }
    var tabBarController: UITabBarController? {
        return window?.rootViewController as? UITabBarController
    }
    var homeVC: HomeViewController? {
        return getController(.home)     as? HomeViewController
    }
    var subjectsVC: SubjectsViewController? {
        return getController(.subjects) as? SubjectsViewController
    }
    var careerVC: CareerViewController? {
        return getController(.career)   as? CareerViewController
    }
    var mapVC: MapViewController? {
        return getController(.map)      as? MapViewController
    }
    var releaseVersionOfLastExecution: String? {
        UserDefaults().synchronize()
        return UserDefaults().string(forKey: kReleaseVersionOfLastExecutionKey)
    }
    var isFirstTimeWithThisRelease: Bool {
        return Bundle.main.releaseVersionNumber != releaseVersionOfLastExecution
    }
    var isFirstTimeWithThisApp: Bool {
        return releaseVersionOfLastExecution == nil
    }
    
    
    func applicationDidFinishLaunching(_ application: UIApplication) {
        
        migrateFromOlderReleaseIfNeeded()
        
        window?.makeKeyAndVisible()
        tabBarController?.delegate = self
        
        if isFirstTimeWithThisApp {
            firstTimeWithThisApp()
        } else if isFirstTimeWithThisRelease {
            firstTimeWithThisRelease()
        } else {
            login()
        }
    }
    
    func login() {
        
        homeVC?.status = .logginIn
        subjectsVC?.status = .logginIn
        careerVC?.status = .logginIn
        mapVC?.status = .logginIn
        
        if let account = storedAccount() {
            
            session?.account = account
            session?.delegate = self
            
            if account == kDemoAccount {
                session?.shouldLoadTestData = true
            }
            
            session?.open()
        } else {
            
            // User has to login
            presentSignInViewController()
        }
    }
    
    func logout() {
        session?.close()
    }
    
    private var previousSelection: ControllerIndex = .home
    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        
        guard let index = ControllerIndex(rawValue: tabBarController.selectedIndex) else {
            return
        }
        
        switch index {
        case .home:
            homeVC?.handleTabBarItemSelection(wasAlreadySelected: previousSelection == .home)
        case .subjects:
            subjectsVC?.handleTabBarItemSelection(wasAlreadySelected: previousSelection == .subjects)
        case .career:
            careerVC?.handleTabBarItemSelection(wasAlreadySelected: previousSelection == .career)
        case .map:
            mapVC?.handleTabBarItemSelection(wasAlreadySelected: previousSelection == .map)
        }
        
        previousSelection = index
    }
    
    
    
    // MARK: Migration & FirstTime assistance methods
    
    func migrateFromOlderReleaseIfNeeded() {
        
        let userDefaults = UserDefaults()
        userDefaults.synchronize()
        
        if userDefaults.string(forKey: "firstExe") != nil {
            
            // User updated from 1.x.x
            
            PTKeychain.removeAllValues()
            
            if let bundleIdentifier = Bundle.main.bundleIdentifier {
                userDefaults.removePersistentDomain(forName: bundleIdentifier)
            }
            
            emptyDocumentsDirectory()
            
            userDefaults.set("1.x.x", forKey: kReleaseVersionOfLastExecutionKey)
        }
    }
    
    func firstTimeWithThisRelease() {
        
        // TODO: Add welcome & what's new message
        let alert = UIAlertController(title: ~"Welcome", message: ~"firstTimeWithThisRelease", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: ~"Continue", style: .default, handler: {
            action in
            self.updateVersionOfLastExecution()
            self.login()
        }))
        window?.rootViewController?.present(alert, animated: true, completion: nil)
    }
    
    func firstTimeWithThisApp() {
        
        // Removes any trace of previous versions that were deleted
        PTKeychain.removeAllValues()
        
        presentSignInViewController(completion: {
            signInController in
            
            let alert = UIAlertController(title: ~"Welcome", message: ~"Thank you for downloading iPoliTO!", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: ~"Continue", style: .default, handler: {
                action in
                self.updateVersionOfLastExecution()
            }))
            signInController.present(alert, animated: true, completion: nil)
        })
    }
    
    func updateVersionOfLastExecution() {
        
        guard let release = Bundle.main.releaseVersionNumber else { return }
        UserDefaults().set(release, forKey: kReleaseVersionOfLastExecutionKey)
    }
    
    func emptyDocumentsDirectory() {
        
        if let documentDirectory =
            NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first {
            
            let fileManager = FileManager()
            
            let paths: [String]
            do {
                try paths = fileManager.contentsOfDirectory(atPath: documentDirectory)
            } catch _ {
                paths = []
            }
            
            for path in paths {
                
                let fullPath = (documentDirectory as NSString).appendingPathComponent(path)
                do {
                    try fileManager.removeItem(atPath: fullPath)
                } catch _ {}
            }
        }
    }
    
    
    
    // MARK: PTSession delegate methods
    
    func sessionDidFinishOpening() {
        
        print("sessionDidFinishOpening")
        guard let session = session else { return }
        
        mapVC?.status = .ready
        
        if session.passedExams == nil || session.studentInfo == nil || session.subjects == nil {
            
            // Some info might be missing!
            let alert = UIAlertController(title: ~"Oops!", message: ~"There was a problem while downloading the data. Some information might be missing.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: ~"Dismiss", style: .cancel, handler: nil))
            window?.rootViewController?.present(alert, animated: true, completion: nil)
        }
        
        if let passedExams = session.passedExams {
            
            careerVC?.passedExams = passedExams
        }
        
        careerVC?.status = .fetching
        session.requestTemporaryGrades()
        
        homeVC?.status = .fetching
        session.requestSchedule()
        
        if let subjects = self.session?.subjects {
            
            subjectsVC?.subjects = subjects
            
            if subjects.isEmpty {
                subjectsVC?.status = .ready
            } else {
                subjectsVC?.status = .fetching
                session.requestDataForSubjects(subjects: subjects)
            }
            
        }
    }
    
    func sessionDidFailOpeningWithError(error: PTRequestError) {
        
        print("sessionDidFailOpeningWithError: \(error)")
        
        homeVC?.status = .error
        subjectsVC?.status = .error
        careerVC?.status = .error
        mapVC?.status = .error
        
        switch error {
        case .InvalidCredentials:
            // Presents login window
            presentSignInViewController()
        default:
            presentLoginErrorAlert(error: error)
            break
        }
    }
    
    
    func managerDidRetrieveSchedule(schedule: [PTLecture]) {
        
        print("managerDidRetrieveSchedule")
        
        homeVC?.schedule = schedule
        homeVC?.status = .ready
    }
    
    func managerDidFailRetrievingScheduleWithError(error: PTRequestError) {
        
        print("managerDidFailRetrievingScheduleWithError: \(error)")
        
        homeVC?.status = .error
    }
    
    
    func managerDidRetrieveTemporaryGrades(_ temporaryGrades: [PTTemporaryGrade]) {
        
        careerVC?.temporaryGrades = temporaryGrades
        careerVC?.status = .ready
    }
    
    func managerDidFailRetrievingTemporaryGradesWithError(error: PTRequestError) {
        careerVC?.status = .error
    }
    
    
    func managerDidRetrieveSubjectData(data: PTSubjectData, subject: PTSubject) {
        
        print("managerDidRetrieveSubjectData:_, subject: \(subject.name)")
        
        subjectsVC?.dataOfSubjects[subject] = data
        
        if session?.dataOfSubjects.count == session?.subjects?.count {
            subjectsVC?.status = .ready
        }
    }
    
    func managerDidFailRetrievingSubjectDataWithError(error: PTRequestError, subject: PTSubject) {
        
        print("managerDidFailRetrievingSubjectDataWithError: \(error), subject: \(subject.name)")
        
        subjectsVC?.dataOfSubjects[subject] = PTSubjectData.invalid
    }
    
    
    func sessionDidFinishClosing() {
        presentSignInViewController()
    }
    
    func sessionDidFailClosingWithError(error: PTRequestError) {
        let alert = UIAlertController(title: ~"Oops!", message: ~"Could not logout at this time!", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: ~"Dismiss", style: .cancel, handler: nil))
        window?.rootViewController?.present(alert, animated: true, completion: nil)
    }
    
    
    
    // MARK: Utilities
    
    func showMapViewController(withHighlightedRoom room: PTRoom? = nil) {
        
        mapVC?.shouldFocus(onRoom: room)
        selectController(.map)
    }
    
    func presentLoginErrorAlert(error: PTRequestError) {
        
        let alert = UIAlertController(title: ~"Oops...", message: nil, preferredStyle: .alert)
        
        alert.message = {
            switch (error) {
            case .NotConnectedToInternet:
                return ~"You're not connected to the internet!"
            case .ServerUnreachable:
                return ~"Servers unreachable or under maintenance!"
            case .TimedOut:
                return ~"Request took too long! Try again."
            default:
                return ~"An unknown error has occurred!"
            }
        }()
        
        alert.addAction(UIAlertAction(title: ~"Retry", style: .default, handler: {
            action in
            self.login()
        }))
        
        window?.rootViewController?.present(alert, animated: true)
    }

    func presentSignInViewController(completion: ((SignInViewController) -> Void)? = nil) {
        
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        guard let signInController = storyboard.instantiateViewController(withIdentifier: "SignInViewController_id") as? SignInViewController,
        let presenterController = window?.rootViewController else {
            return
        }
        
        presenterController.modalPresentationStyle = .currentContext
        presenterController.present(signInController, animated: true, completion: {
            completion?(signInController)
        })
    }
    
    func selectController(_ index: ControllerIndex) {
        tabBarController?.selectedIndex = index.rawValue
    }
    
    func getController(_ index: ControllerIndex) -> UIViewController? {
        let navCtrl = tabBarController?.viewControllers?[index.rawValue] as? UINavigationController
        
        return navCtrl?.viewControllers.first
    }
}


private func storedAccount() -> PTAccount? {
    
    if kDebugForcePresentLoginVC {
        return nil
    }
    
    if kDebugShouldForceCredentials {
        return kDebugForcingCredentials
    }
    
    return PTKeychain.retrieveAccount()
}

