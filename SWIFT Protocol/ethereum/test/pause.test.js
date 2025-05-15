const {
	expect
} = require("chai");
const hre = require("hardhat");
const {
	ethers
} = hre;
describe("SWIFT Protocol Emergency & Pause Functions", () => {
	let swift, deployer, user, mod;
	const reason = ethers.encodeBytes32String("test emergency");
	beforeEach(async () => {
		[deployer, user, mod] = await ethers.getSigners();
		const Swift = await ethers.getContractFactory("SWIFTProtocol");
		swift = await Swift.deploy({
			value: ethers.parseEther("0.01")
		});
		await swift.waitForDeployment();
	});
	describe("Emergency Stop", () => {
		it("should allow admin to activate emergency stop", async () => {
			await expect(swift.emergencyStop(reason)).to.emit(swift, "EmergencyStopActivated");
			expect(await swift.isEmergencyStopped()).to.equal(true);
		});
		it("should prevent non-admin from activating emergency stop", async () => {
			await expect(swift.connect(user).emergencyStop(reason)).to.be.revertedWith("Not admin");
		});
		it("should pause contract when emergency is activated if not already paused", async () => {
			expect(await swift.paused()).to.equal(false);
			await swift.emergencyStop(reason);
			expect(await swift.paused()).to.equal(true);
		});
		it("should remember previous pause state when emergency is activated", async () => {
			await swift.pause();
			expect(await swift.paused()).to.equal(true);
			await swift.emergencyStop(reason);
			expect(await swift.paused()).to.equal(true);
			await swift.liftEmergencyStop();
			expect(await swift.paused()).to.equal(true);
			await swift.unpause();
			expect(await swift.paused()).to.equal(false);
		});
		it("should allow admin to lift emergency stop", async () => {
			await swift.emergencyStop(reason);
			await expect(swift.liftEmergencyStop()).to.emit(swift, "EmergencyStopLifted");
			expect(await swift.isEmergencyStopped()).to.equal(false);
		});
		it("should prevent non-admin from lifting emergency stop", async () => {
			await swift.emergencyStop(reason);
			await expect(swift.connect(user).liftEmergencyStop()).to.be.revertedWith("Not admin");
		});
		it("should prevent functions with emergencyNotActive modifier during emergency", async () => {
			await swift.emergencyStop(reason);
			await expect(swift.grantRole(await swift.modRole(), user.address)).to.be.revertedWith("Emergency stop active");
		});
	});
	describe("Pause Functions", () => {
		beforeEach(async () => {
			await swift.grantRole(await swift.modRole(), mod.address);
		});
		it("should allow admin or mod to pause", async () => {
			await expect(swift.connect(mod).pause()).to.emit(swift, "Paused");
			expect(await swift.paused()).to.equal(true);
		});
		it("should prevent non-admin/mod from pausing", async () => {
			await expect(swift.connect(user).pause()).to.be.revertedWith("Caller is not admin or mod");
		});
		it("should allow admin or mod to unpause", async () => {
			await swift.pause();
			await expect(swift.connect(mod).unpause()).to.emit(swift, "Unpaused");
			expect(await swift.paused()).to.equal(false);
		});
		it("should prevent non-admin/mod from unpausing", async () => {
			await swift.pause();
			await expect(swift.connect(user).unpause()).to.be.revertedWith("Caller is not admin or mod");
		});
		it("should not allow pause during emergency stop", async () => {
			await swift.emergencyStop(reason);
			await expect(swift.pause()).to.be.revertedWith("Emergency stop active");
		});
		it("should not allow unpause during emergency stop", async () => {
			await swift.pause();
			await swift.emergencyStop(reason);
			await expect(swift.unpause()).to.be.revertedWith("Emergency stop active");
		});
	});
	describe("Function Blocking", () => {
		it("should block whenNotPaused function while paused", async () => {
			await swift.pause();
			await expect(swift.multiTransfer(0, ethers.ZeroAddress,
				[user.address],
				[1],
				[], false, ethers.ZeroHash, {
					value: ethers.parseEther("0.001")
				})).to.be.revertedWithCustomError(swift, "EnforcedPause");
		});
		it("should block whenNotPaused function while emergency stop active", async () => {
			await swift.emergencyStop(reason);
			await expect(swift.multiTransfer(0, ethers.ZeroAddress,
				[user.address],
				[1],
				[], false, ethers.ZeroHash, {
					value: ethers.parseEther("0.001")
				})).to.be.revertedWithCustomError(swift, "EnforcedPause");
		});
	});
	describe("Withdrawal Functions", () => {
		beforeEach(async () => {
			await deployer.sendTransaction({
				to: await swift.getAddress(),
				value: ethers.parseEther("0.002")
			});
		});
		describe("requestWithdrawal", () => {
			it("should revert when paused", async () => {
				await swift.pause();
				await expect(swift.requestWithdrawal(ethers.parseEther("0.001"), ethers.encodeBytes32String("isETH"), ethers.ZeroAddress, 0)).to.be.revertedWithCustomError(swift, "EnforcedPause");
			});
			it("should revert during emergency stop", async () => {
				await swift.emergencyStop(reason);
				await expect(swift.requestWithdrawal(ethers.parseEther("0.001"), ethers.encodeBytes32String("isETH"), ethers.ZeroAddress, 0)).to.be.reverted;
			});
			it("should succeed when not paused and no emergency", async () => {
				await expect(swift.requestWithdrawal(ethers.parseEther("0.001"), ethers.encodeBytes32String("isETH"), ethers.ZeroAddress, 0)).to.emit(swift, "WithdrawalRequested");
			});
		});
		describe("cancelWithdrawal", () => {
			beforeEach(async () => {
				await swift.requestWithdrawal(ethers.parseEther("0.001"), ethers.encodeBytes32String("isETH"), ethers.ZeroAddress, 0);
			});
			it("should revert during emergency stop", async () => {
				await swift.emergencyStop(reason);
				await expect(swift.cancelWithdrawal()).to.be.revertedWith("Emergency stop active");
			});
			it("should succeed when not in emergency", async () => {
				await expect(swift.cancelWithdrawal()).to.emit(swift, "WithdrawalCancelled");
			});
		});
		describe("completeWithdrawal", () => {
			beforeEach(async () => {
				await swift.requestWithdrawal(ethers.parseEther("0.001"), ethers.encodeBytes32String("isETH"), ethers.ZeroAddress, 0);
				await ethers.provider.send("evm_increaseTime", [86400 + 1]);
				await ethers.provider.send("evm_mine");
			});
			it("should revert during emergency stop", async () => {
				await swift.emergencyStop(reason);
				await expect(swift.completeWithdrawal()).to.be.revertedWith("Emergency stop active");
			});
			it("should succeed when not in emergency", async () => {
				await expect(swift.completeWithdrawal()).to.emit(swift, "WithdrawalCompleted");
			});
			it("should revert if withdrawal delay not passed", async () => {
				await swift.cancelWithdrawal();
				await swift.requestWithdrawal(ethers.parseEther("0.001"), ethers.encodeBytes32String("isETH"), ethers.ZeroAddress, 0);
				await expect(swift.completeWithdrawal()).to.be.revertedWith("The locking period has not expired yet");
			});
		});
	});
});