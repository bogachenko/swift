const {
	expect
} = require("chai");
const hre = require("hardhat");
const {
	ethers
} = hre;
describe("SWIFT Protocol Emergency & Pause Functions", () => {
	let swift;
	let deployer, user, mod;
	const reason = ethers.encodeBytes32String("test emergency");
	beforeEach(async () => {
		[deployer, user, mod] = await ethers.getSigners();
		const Swift = await ethers.getContractFactory("SWIFTProtocol");
		swift = await Swift.deploy({
			value: ethers.parseEther("0.01")
		});
		await swift.waitForDeployment();
		await swift.connect(deployer).grantRole(await swift.modRole(), mod.address);
	});
	const activateEmergencyStop = async (actor = deployer) => swift.connect(actor).emergencyStop(reason);
	const liftEmergencyStop = async (actor = deployer) => swift.connect(actor).liftEmergencyStop();
	const pauseContract = async (actor = deployer) => swift.connect(actor).pause();
	const unpauseContract = async (actor = deployer) => swift.connect(actor).unpause();
	const requestWithdrawal = async () => swift.requestWithdrawal(ethers.parseEther("0.001"), ethers.encodeBytes32String("isETH"), ethers.ZeroAddress, 0);
	const cancelWithdrawal = async () => swift.cancelWithdrawal();
	const completeWithdrawal = async () => swift.completeWithdrawal();
	const sendETHToContract = async (sender, amount) => sender.sendTransaction({
		to: await swift.getAddress(),
		value: amount
	});
	describe("Emergency Stop", () => {
		it("should allow admin to activate emergency stop", async () => {
			await expect(activateEmergencyStop()).to.emit(swift, "EmergencyStopActivated");
			expect(await swift.isEmergencyStopped()).to.be.true;
		});
		it("should prevent non-admin from activating emergency stop", async () => {
			await expect(activateEmergencyStop(user)).to.be.revertedWith("Not admin");
		});
		it("should pause contract when emergency is activated if not already paused", async () => {
			expect(await swift.paused()).to.be.false;
			await activateEmergencyStop();
			expect(await swift.paused()).to.be.true;
		});
		it("should remember previous pause state when emergency is activated", async () => {
			await pauseContract();
			expect(await swift.paused()).to.be.true;
			await activateEmergencyStop();
			expect(await swift.paused()).to.be.true;
			await liftEmergencyStop();
			expect(await swift.paused()).to.be.true;
			await unpauseContract();
			expect(await swift.paused()).to.be.false;
		});
		it("should allow admin to lift emergency stop", async () => {
			await activateEmergencyStop();
			await expect(liftEmergencyStop()).to.emit(swift, "EmergencyStopLifted");
			expect(await swift.isEmergencyStopped()).to.be.false;
		});
		it("should prevent non-admin from lifting emergency stop", async () => {
			await activateEmergencyStop();
			await expect(liftEmergencyStop(user)).to.be.revertedWith("Not admin");
		});
		it("should prevent functions with emergencyNotActive modifier during emergency", async () => {
			await activateEmergencyStop();
			await expect(swift.grantRole(await swift.modRole(), user.address)).to.be.revertedWith("Emergency stop active");
		});
	});
	describe("Pause Functions", () => {
		it("should allow admin or mod to pause", async () => {
			await expect(pauseContract(mod)).to.emit(swift, "Paused");
			expect(await swift.paused()).to.be.true;
		});
		it("should prevent non-admin/mod from pausing", async () => {
			await expect(pauseContract(user)).to.be.revertedWith("Caller is not admin or mod");
		});
		it("should allow admin or mod to unpause", async () => {
			await pauseContract();
			await expect(unpauseContract(mod)).to.emit(swift, "Unpaused");
			expect(await swift.paused()).to.be.false;
		});
		it("should prevent non-admin/mod from unpausing", async () => {
			await pauseContract();
			await expect(unpauseContract(user)).to.be.revertedWith("Caller is not admin or mod");
		});
		it("should not allow pause during emergency stop", async () => {
			await activateEmergencyStop();
			await expect(pauseContract()).to.be.revertedWith("Emergency stop active");
		});
		it("should not allow unpause during emergency stop", async () => {
			await pauseContract();
			await activateEmergencyStop();
			await expect(unpauseContract()).to.be.revertedWith("Emergency stop active");
		});
	});
	describe("Function Blocking", () => {
		it("should block whenNotPaused function while paused", async () => {
			await pauseContract();
			await expect(swift.multiTransfer(0, ethers.ZeroAddress, [user.address], [1], [], false, ethers.ZeroHash, {
				value: ethers.parseEther("0.001"),
			})).to.be.revertedWithCustomError(swift, "EnforcedPause");
		});
		it("should block whenNotPaused function while emergency stop active", async () => {
			await activateEmergencyStop();
			await expect(swift.multiTransfer(0, ethers.ZeroAddress, [user.address], [1], [], false, ethers.ZeroHash, {
				value: ethers.parseEther("0.001"),
			})).to.be.revertedWithCustomError(swift, "EnforcedPause");
		});
	});
	describe("Withdrawal Functions", () => {
		beforeEach(async () => {
			await sendETHToContract(deployer, ethers.parseEther("0.002"));
		});
		describe("requestWithdrawal", () => {
			it("should revert when paused", async () => {
				await pauseContract();
				await expect(requestWithdrawal()).to.be.revertedWithCustomError(swift, "EnforcedPause");
			});
			it("should revert during emergency stop", async () => {
				await activateEmergencyStop();
				await expect(requestWithdrawal()).to.be.reverted;
			});
			it("should succeed when not paused and no emergency", async () => {
				await expect(requestWithdrawal()).to.emit(swift, "WithdrawalRequested");
			});
		});
		describe("cancelWithdrawal", () => {
			beforeEach(async () => {
				await requestWithdrawal();
			});
			it("should revert during emergency stop", async () => {
				await activateEmergencyStop();
				await expect(cancelWithdrawal()).to.be.revertedWith("Emergency stop active");
			});
			it("should succeed when not in emergency", async () => {
				await expect(cancelWithdrawal()).to.emit(swift, "WithdrawalCancelled");
			});
		});
		describe("completeWithdrawal", () => {
			beforeEach(async () => {
				await requestWithdrawal();
				await ethers.provider.send("evm_increaseTime", [86400 + 1]);
				await ethers.provider.send("evm_mine");
			});
			it("should revert during emergency stop", async () => {
				await activateEmergencyStop();
				await expect(completeWithdrawal()).to.be.revertedWith("Emergency stop active");
			});
			it("should succeed when not in emergency", async () => {
				await expect(completeWithdrawal()).to.emit(swift, "WithdrawalCompleted");
			});
			it("should revert if withdrawal delay not passed", async () => {
				await cancelWithdrawal();
				await requestWithdrawal();
				await expect(completeWithdrawal()).to.be.revertedWith("The locking period has not expired yet");
			});
		});
	});
});