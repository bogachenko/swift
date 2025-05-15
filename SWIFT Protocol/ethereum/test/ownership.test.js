const {
	expect
} = require("chai");
const {
	ethers
} = require("hardhat");
describe("SWIFT Protocol Ownership Functions", function() {
	let swift;
	let owner, admin1, admin2, pendingOwner, nonAdmin;
	before(async function() {
		[owner, admin1, admin2, pendingOwner, nonAdmin] = await ethers.getSigners();
		const SWIFTProtocolFactory = await ethers.getContractFactory("SWIFTProtocol");
		swift = await SWIFTProtocolFactory.deploy({
			value: 1
		});
		await swift.connect(owner).grantRole(await swift.adminRole(), admin1.address);
		await swift.connect(owner).grantRole(await swift.adminRole(), admin2.address);
	});
	describe("transferOwnership", function() {
		it("should allow admin to initiate ownership transfer", async function() {
			await swift.connect(admin1).transferOwnership(pendingOwner.address);
			expect(await swift.pendingOwner()).to.equal(pendingOwner.address);
		});
		it("should emit OwnershipTransferInitiated event", async function() {
			await expect(swift.connect(admin1).transferOwnership(pendingOwner.address)).to.emit(swift, "OwnershipTransferInitiated").withArgs(await swift.owner(), pendingOwner.address);
		});
		it("should reject non-admin from initiating transfer", async function() {
			await expect(swift.connect(nonAdmin).transferOwnership(pendingOwner.address)).to.be.revertedWith("Not admin");
		});
		it("should reject zero address as new owner", async function() {
			await expect(swift.connect(admin1).transferOwnership(ethers.ZeroAddress)).to.be.revertedWith("Invalid owner address");
		});
	});
	describe("acceptOwnership", function() {
		beforeEach(async function() {
			await swift.connect(admin1).transferOwnership(pendingOwner.address);
		});
		it("should allow pending owner to accept ownership", async function() {
			await swift.connect(pendingOwner).acceptOwnership();
			expect(await swift.owner()).to.equal(pendingOwner.address);
			expect(await swift.pendingOwner()).to.equal(ethers.ZeroAddress);
		});
		it("should emit OwnershipTransferred event", async function() {
			const previousOwner = await swift.owner();
			await expect(swift.connect(pendingOwner).acceptOwnership()).to.emit(swift, "OwnershipTransferred").withArgs(previousOwner, pendingOwner.address);
		});
		it("should reject non-pending owner from accepting", async function() {
			await expect(swift.connect(nonAdmin).acceptOwnership()).to.be.revertedWith("Not pending owner");
		});
		it("should reject when no pending owner exists", async function() {
			await swift.connect(pendingOwner).acceptOwnership();
			await expect(swift.connect(pendingOwner).acceptOwnership()).to.be.revertedWith("No pending owner");
		});
	});
	describe("renounceOwnership", function() {
		it("should allow admin to renounce ownership", async function() {
			if((await swift.pendingOwner()) !== ethers.ZeroAddress) {
				const pending = await swift.pendingOwner();
				const pendingSigner = await ethers.getImpersonatedSigner(pending);
				await swift.connect(pendingSigner).acceptOwnership();
			}
			await swift.connect(admin1).renounceOwnership();
			expect(await swift.owner()).to.equal(ethers.ZeroAddress);
		});
		it("should emit OwnershipRenounced event", async function() {
			const previousOwner = await swift.owner();
			await expect(swift.connect(admin1).renounceOwnership()).to.emit(swift, "OwnershipRenounced").withArgs(previousOwner);
		});
		it("should reject non-admin from renouncing", async function() {
			await expect(swift.connect(nonAdmin).renounceOwnership()).to.be.revertedWith("Not admin");
		});
		it("should reject if pending owner exists", async function() {
			await swift.connect(admin1).transferOwnership(pendingOwner.address);
			await expect(swift.connect(admin1).renounceOwnership()).to.be.revertedWith("Pending owner exists");
		});
		it("should make contract ownerless after renouncing", async function() {
			if((await swift.pendingOwner()) !== ethers.ZeroAddress) {
				const pending = await swift.pendingOwner();
				const pendingSigner = await ethers.getImpersonatedSigner(pending);
				await swift.connect(pendingSigner).acceptOwnership();
			}
			await swift.connect(admin1).renounceOwnership();
			expect(await swift.owner()).to.equal(ethers.ZeroAddress);
			await expect(swift.connect(admin1).transferOwnership(pendingOwner.address)).to.emit(swift, "OwnershipTransferInitiated");
		});
	});
	describe("ownership lifecycle", function() {
		it("should complete full ownership transfer cycle", async function() {
			const originalOwner = await swift.owner();
			await swift.connect(admin1).transferOwnership(pendingOwner.address);
			expect(await swift.pendingOwner()).to.equal(pendingOwner.address);
			expect(await swift.owner()).to.equal(originalOwner);
			await swift.connect(pendingOwner).acceptOwnership();
			expect(await swift.owner()).to.equal(pendingOwner.address);
			expect(await swift.pendingOwner()).to.equal(ethers.ZeroAddress);
			const isAdmin = await swift.hasRole(await swift.adminRole(), admin2.address);
			if(!isAdmin) {
				await swift.connect(pendingOwner).grantRole(await swift.adminRole(), admin2.address);
			}
			await swift.connect(pendingOwner).transferOwnership(admin2.address);
			expect(await swift.pendingOwner()).to.equal(admin2.address);
		})
		it("should allow cancellation by initiating new transfer", async function() {
			await swift.connect(admin1).transferOwnership(pendingOwner.address);
			await swift.connect(admin1).transferOwnership(admin2.address);
			expect(await swift.pendingOwner()).to.equal(admin2.address);
			await expect(swift.connect(pendingOwner).acceptOwnership()).to.be.revertedWith("Not pending owner");
		});
	});
});