const {
	expect
} = require("chai");
const hre = require("hardhat");
const {
	ethers
} = hre;
describe("SWIFT Protocol Role Management", () => {
	let swift, deployer, admin, mod, user1, user2, user3;
	beforeEach(async () => {
		const signers = await ethers.getSigners();
		deployer = signers[0];
		admin = signers[1];
		mod = signers[2];
		user1 = signers[3];
		user2 = signers[4];
		user3 = signers[5];
		const Swift = await ethers.getContractFactory("SWIFTProtocol");
		swift = await Swift.deploy({
			value: ethers.parseEther("0.01")
		});
		await swift.waitForDeployment();
		await swift.grantRole(await swift.adminRole(), admin.address);
		await swift.grantRole(await swift.modRole(), mod.address);
	});
	describe("grantRole Function", () => {
		it("should allow admin to grant admin role", async () => {
			await swift.connect(admin).grantRole(await swift.adminRole(), user1.address);
			expect(await swift.hasRole(await swift.adminRole(), user1.address)).to.be.true;
		});
		it("should allow admin to grant mod role", async () => {
			await swift.connect(admin).grantRole(await swift.modRole(), user1.address);
			expect(await swift.hasRole(await swift.modRole(), user1.address)).to.be.true;
		});
		it("should prevent non-admin from granting roles", async () => {
			await expect(swift.connect(mod).grantRole(await swift.modRole(), user1.address)).to.be.revertedWith("Not admin");
		});
		it("should enforce max admin limit", async () => {
			await swift.connect(admin).grantRole(await swift.adminRole(), user1.address);
			await expect(swift.connect(admin).grantRole(await swift.adminRole(), user2.address)).to.be.revertedWith("Max admins");
		});
		it("should enforce max mod limit", async () => {
			const signers = await ethers.getSigners();
			const maxMods = Number(await swift.maxMods());
			for(let i = 0; i < maxMods - 1; i++) {
				await swift.connect(admin).grantRole(await swift.modRole(), signers[i + 6].address);
			}
			await expect(swift.connect(admin).grantRole(await swift.modRole(), signers[maxMods + 5].address)).to.be.revertedWith("Max mods");
		});
		it("should prevent granting role to zero address", async () => {
			await expect(swift.connect(admin).grantRole(await swift.modRole(), ethers.ZeroAddress)).to.be.revertedWith("Cannot grant role to zero address");
		});
		it("should prevent granting role to a contract", async () => {
			const Dummy = await ethers.getContractFactory("SWIFTProtocol");
			const deployedContract = await Dummy.deploy();
			await deployedContract.waitForDeployment();
			await expect(swift.connect(admin).grantRole(await swift.adminRole(), deployedContract.target)).to.be.revertedWith("Cannot grant role to a contract");
		});
		it("should prevent granting role to an address that already has it", async () => {
			await swift.connect(admin).grantRole(await swift.modRole(), user1.address);
			await expect(swift.connect(admin).grantRole(await swift.modRole(), user1.address)).to.be.revertedWith("Account already has this role");
		});
		it("should emit RoleGranted event", async () => {
			await expect(swift.connect(admin).grantRole(await swift.modRole(), user1.address)).to.emit(swift, "RoleGranted").withArgs(await swift.modRole(), user1.address, admin.address);
		});
		it("should prevent role granting during emergency stop", async () => {
			await swift.connect(admin).emergencyStop(ethers.encodeBytes32String("test"));
			await expect(swift.connect(admin).grantRole(await swift.modRole(), user1.address)).to.be.revertedWith("Emergency stop active");
		});
	});
	describe("revokeRole Function", () => {
		beforeEach(async () => {
			await swift.connect(admin).grantRole(await swift.adminRole(), user1.address);
			await swift.connect(admin).grantRole(await swift.modRole(), user2.address);
		});
		it("should allow admin to revoke admin role", async () => {
			await swift.connect(admin).revokeRole(await swift.adminRole(), user1.address);
			expect(await swift.hasRole(await swift.adminRole(), user1.address)).to.be.false;
		});
		it("should allow admin to revoke mod role", async () => {
			await swift.connect(admin).revokeRole(await swift.modRole(), user2.address);
			expect(await swift.hasRole(await swift.modRole(), user2.address)).to.be.false;
		});
		it("should prevent non-admin from revoking roles", async () => {
			await expect(swift.connect(mod).revokeRole(await swift.modRole(), user2.address)).to.be.revertedWith("Not admin");
		});
		it("should prevent removing the last admin", async () => {
			await swift.connect(admin).revokeRole(await swift.adminRole(), deployer.address);
			await swift.connect(admin).revokeRole(await swift.adminRole(), user1.address);
			await expect(swift.connect(admin).revokeRole(await swift.adminRole(), admin.address)).to.be.revertedWith("Cannot remove last admin");
		});
		it("should allow self-removal of mod role", async () => {
			await swift.connect(admin).grantRole(await swift.modRole(), admin.address);
			await swift.connect(admin).revokeRole(await swift.modRole(), admin.address);
			expect(await swift.hasRole(await swift.modRole(), admin.address)).to.be.false;
		});
		it("should prevent self-removal of admin role", async () => {
			await expect(swift.connect(admin).revokeRole(await swift.adminRole(), admin.address)).to.be.revertedWith("Self-removal forbidden");
		});
		it("should emit RoleRevoked event", async () => {
			await expect(swift.connect(admin).revokeRole(await swift.modRole(), user2.address)).to.emit(swift, "RoleRevoked").withArgs(await swift.modRole(), user2.address, admin.address);
		});
		it("should prevent role revocation during emergency stop", async () => {
			await swift.connect(admin).emergencyStop(ethers.encodeBytes32String("test"));
			await expect(swift.connect(admin).revokeRole(await swift.modRole(), user2.address)).to.be.revertedWith("Emergency stop active");
		});
		it("should allow revoking non-existent roles", async () => {
			await swift.connect(admin).revokeRole(await swift.modRole(), user3.address);
			expect(await swift.hasRole(await swift.modRole(), user3.address)).to.be.false;
		});
	});
	describe("Role Admin Management", () => {
		it("should have adminRole as admin of itself", async () => {
			expect(await swift.getRoleAdmin(await swift.adminRole())).to.equal(await swift.adminRole());
		});
		it("should have adminRole as admin of modRole", async () => {
			expect(await swift.getRoleAdmin(await swift.modRole())).to.equal(await swift.adminRole());
		});
	});
});