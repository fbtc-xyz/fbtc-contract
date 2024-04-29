// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {Request, RequestLib, Operation, ChainCode} from "./Common.sol";
import {BridgeStorage} from "./BridgeStorage.sol";
import {FToken} from "./FToken.sol";
import {Governable} from "./Governable.sol";
import {FeeModel} from "./FeeModel.sol";

contract FireBridge is BridgeStorage, Governable {
    using RequestLib for Request;
    using EnumerableSet for EnumerableSet.AddressSet;

    event QualifiedUserAdded(
        address indexed _user,
        bytes _depositAddress,
        bytes _withdrawalAddress
    );
    event QualifiedUserEdited(
        address indexed _user,
        bytes _depositAddress,
        bytes _withdrawalAddress
    );

    event QualifiedUserRemoved(address indexed _user);

    event TokenSet(address indexed _token);
    event MinterSet(address indexed _minter);
    event FeeModelSet(address indexed _feeModel);
    event FeeRecipientSet(address indexed _feeRecipient);

    event RequestAdded(bytes32 indexed _hash, Operation indexed op, Request _r);
    event RequestConfirmed(bytes32 indexed _hash);

    event FeePaid(address indexed _feeRecipient, uint256 indexed _feeAmount);

    modifier onlyMinter() {
        require(msg.sender == minter, "Caller not minter");
        _;
    }

    modifier onlyQualifiedUser() {
        require(
            qualifiedUsers.contains(msg.sender),
            "Caller not qualifiedUser"
        );
        _;
    }

    bytes32 public immutable MAIN_CHAIN;

    constructor(address _owner, bytes32 _mainChain) {
        initialize(_owner);
        MAIN_CHAIN = _mainChain;
    }

    function initialize(address _owner) public initializer {
        __Governable_init(_owner);
        Request memory dummy;
        _addRequest(dummy);
        assert(nonce() == 1); // Force the request id starts from 1.
    }

    function _splitFeeAndUpdate(Request memory r) internal view {
        assert(r.fee == 0);
        uint256 _fee = FeeModel(feeModel).getFee(r);
        r.fee = _fee;
        r.amount = r.amount - _fee;
    }

    function _payFee(uint256 _fee, bool viaMint) internal {
        if (_fee == 0) return;

        address _feeRecipient = feeRecipient;
        if (viaMint) {
            FToken(fbtc).mint(_feeRecipient, _fee);
        } else {
            FToken(fbtc).payFee(msg.sender, _feeRecipient, _fee);
        }
        emit FeePaid(_feeRecipient, _fee);
    }

    function _addRequest(Request memory r) internal returns (bytes32 _hash) {
        assert(r.nonce == requestHashes.length);
        _hash = r.getRequestHash();
        requestHashes.push(_hash);
        requests[_hash] = r;
        emit RequestAdded(_hash, r.op, r);
    }

    /// Owner methods.
    function addQualifiedUser(
        address _user,
        bytes calldata _depositAddress,
        bytes calldata _withdrawalAddress
    ) external onlyOwner {
        require(qualifiedUsers.add(_user), "User already qualified");
        require(
            depositAddressToUser[_depositAddress] == address(0),
            "Deposit address used"
        );
        depositAddresses[_user] = _depositAddress;
        withdrawalAddresses[_user] = _withdrawalAddress;
        depositAddressToUser[_depositAddress] = _user;
        emit QualifiedUserAdded(_user, _depositAddress, _withdrawalAddress);
    }

    function editQualifiedUser(
        address _user,
        bytes calldata _depositAddress,
        bytes calldata _withdrawalAddress
    ) external onlyOwner {
        require(isQualifiedUser(_user), "User not qualified");
        require(
            depositAddressToUser[_depositAddress] == address(0),
            "Deposit address used"
        );

        bytes memory _oldDepositAddress = depositAddresses[_user];
        delete depositAddressToUser[_oldDepositAddress];

        depositAddresses[_user] = _depositAddress;
        withdrawalAddresses[_user] = _withdrawalAddress;
        depositAddressToUser[_depositAddress] = _user;
        emit QualifiedUserEdited(_user, _depositAddress, _withdrawalAddress);
    }

    function removeQualifiedUser(address _qualifiedUser) external onlyOwner {
        qualifiedUsers.remove(_qualifiedUser);
        bytes memory _depositAddress = depositAddresses[_qualifiedUser];
        delete depositAddressToUser[_depositAddress];
        delete depositAddresses[_qualifiedUser];
        delete withdrawalAddresses[_qualifiedUser];
        emit QualifiedUserRemoved(_qualifiedUser);
    }

    function setToken(address _token) external onlyOwner {
        fbtc = _token;
        emit TokenSet(_token);
    }

    function setMinter(address _minter) external onlyOwner {
        minter = _minter;
        emit MinterSet(_minter);
    }

    function setFeeModel(address _feeModel) external onlyOwner {
        feeModel = _feeModel;
        emit FeeModelSet(_feeModel);
    }

    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        feeRecipient = _feeRecipient;
        emit FeeRecipientSet(_feeRecipient);
    }

    /// QualifiedUser methods.

    /// @notice Initiate a FBTC minting request for the qualifiedUser.
    /// @param _amount The amount of FBTC to mint.
    /// @param _depositTxid The BTC deposit txid
    /// @param _outputIndex The transaction output index to user's deposit address.
    /// @return _hash The hash of the new created request.
    /// @return _r The full new created request.
    function addMintRequest(
        uint256 _amount,
        bytes32 _depositTxid,
        uint256 _outputIndex
    )
        external
        onlyQualifiedUser
        whenNotPaused
        returns (bytes32 _hash, Request memory _r)
    {
        // Check request.
        require(_amount > 0, "Invalid amount");
        require(uint256(_depositTxid) != 0, "Empty deposit txid");
        bytes memory _depositTxData = abi.encode(_depositTxid, _outputIndex);

        bytes32 depositDataHash = keccak256(_depositTxData);
        require(!usedDepositTxs[depositDataHash], "Used BTC deposit tx");
        usedDepositTxs[depositDataHash] = true;

        // Compose request. Main -> Self
        _r = Request({
            nonce: nonce(),
            op: Operation.Mint,
            srcChain: MAIN_CHAIN,
            srcAddress: depositAddresses[msg.sender],
            dstChain: chain(),
            dstAddress: abi.encode(msg.sender),
            amount: _amount,
            fee: 0, // To be set in `_splitFeeAndUpdate`
            extra: _depositTxData,
            confirmed: false
        });

        // Split fee.
        _splitFeeAndUpdate(_r);

        // Save request.
        _hash = _addRequest(_r);
    }

    /// @notice Initiate a FBTC burning request for the qualifiedUser.
    /// @param _amount The amount of FBTC to burn.
    /// @return _hash The hash of the new created request.
    /// @return _r The full new created request.
    function addBurnRequest(
        uint256 _amount
    )
        external
        onlyQualifiedUser
        whenNotPaused
        returns (bytes32 _hash, Request memory _r)
    {
        // Check request.
        require(_amount > 0, "Invalid amount");

        // Compose request. Self -> Main
        _r = Request({
            nonce: nonce(),
            op: Operation.Burn,
            srcChain: chain(),
            srcAddress: abi.encode(msg.sender),
            dstChain: MAIN_CHAIN,
            dstAddress: withdrawalAddresses[msg.sender],
            amount: _amount,
            fee: 0, // To be set in `_splitFeeAndUpdate`
            extra: "", // Unset until confirmed
            confirmed: false
        });

        // Split fee.
        _splitFeeAndUpdate(_r);

        // Save request.
        _hash = _addRequest(_r);

        // Pay fee
        _payFee(_r.fee, false);

        // Burn tokens.
        FToken(fbtc).burn(msg.sender, _r.amount);
    }

    /// Customer methods.
    /// @notice Initiate a FBTC cross-chain bridging request.
    /// @param _amount The amount of FBTC to burn.
    /// @return _hash The hash of the new created request.
    /// @return _r The full new created request.
    function addCrosschainRequest(
        bytes32 _targetChain,
        bytes calldata _targetAddress,
        uint256 _amount
    ) external whenNotPaused returns (bytes32 _hash, Request memory _r) {
        // Check request.
        require(_amount > 0, "Invalid amount");

        // Compose request. Self -> Target
        bytes32 _srcChain = chain();
        require(_targetChain != _srcChain, "Self-cross not allowed");

        _r = Request({
            nonce: nonce(),
            op: Operation.CrosschainRequest,
            srcChain: _srcChain,
            srcAddress: abi.encode(msg.sender),
            amount: _amount,
            dstChain: _targetChain,
            dstAddress: _targetAddress,
            fee: 0,
            extra: "", // Not include in hash.
            confirmed: true // auto confirmed.
        });

        // Split fee.
        _splitFeeAndUpdate(_r);

        // Save request.
        _hash = _addRequest(_r);
        _r.extra = abi.encode(_hash); // update return value.
        requests[_hash].extra = abi.encode(_hash); // update storage.

        emit RequestConfirmed(_hash); // auto confirmed.

        // Pay fee
        _payFee(_r.fee, false);

        // Burn tokens.
        FToken(fbtc).burn(msg.sender, _r.amount);
    }

    /// Minter methods.

    /// @notice Confirm the minting request.
    /// @param _hash The minting request hash.
    function confirmMintRequest(
        bytes32 _hash
    ) external onlyMinter whenNotPaused {
        // Check request.
        Request storage r = requests[_hash];
        require(r.op == Operation.Mint, "Not Mint request");

        uint256 _amount = r.amount;
        require(_amount > 0, "Invalid request amount");
        require(!r.confirmed, "Already confirmed");

        // Update status.
        r.confirmed = true;
        emit RequestConfirmed(_hash);

        // Mint tokens
        FToken(fbtc).mint(abi.decode(r.dstAddress, (address)), _amount);

        // Pay fee.
        _payFee(r.fee, true);
    }

    /// @notice Confirm the burning request.
    /// @dev `_withdrawalTxData` packing format is defined by off-chain service.
    /// @param _hash The burning request id.
    /// @param _withdrawalTxid The BTC withdrawal txid
    /// @param _outputIndex The transaction output index to user's withdrawal address.
    function confirmBurnRequest(
        bytes32 _hash,
        bytes32 _withdrawalTxid,
        uint256 _outputIndex
    ) external onlyMinter whenNotPaused {
        // Check request.
        require(uint256(_withdrawalTxid) != 0, "Empty withdraw txid");

        Request storage r = requests[_hash];

        require(r.op == Operation.Burn, "Not Burn request");
        require(r.amount > 0, "Invalid request amount");
        require(!r.confirmed, "Already confirmed");

        bytes memory _withdrawalTxData = abi.encode(
            _withdrawalTxid,
            _outputIndex
        );

        bytes32 _withdrawalDataHash = keccak256(_withdrawalTxData);
        require(
            !usedWithdrawalTxs[_withdrawalDataHash],
            "Used BTC withdrawal tx"
        );
        usedWithdrawalTxs[_withdrawalDataHash] = true;

        // Update status.
        r.confirmed = true;
        r.extra = _withdrawalTxData;

        emit RequestConfirmed(_hash);
    }

    /// @notice Confirm the cross-chain request.
    /// @dev Most fields of the request should be the same as the one on
    ///      source chain. Note:
    ///       1. The `op` should be `CrosschainConfirm`
    ///       2. The `nonce` is the source nonce, used to calc source request hash.
    ///       3. The `confirmed` should be `true`.
    ///       4. The `extra` should contain the source request hash.
    /// @param r The full cross-chain request.
    /// @return _dsthash The hash of the confirmation request.
    function confirmCrosschainRequest(
        Request memory r
    )
        external
        onlyMinter
        whenNotPaused
        returns (bytes32 _dsthash, Request memory _dstRequest)
    {
        // Check request.
        require(r.amount > 0, "Invalid request amount");
        require(r.extra.length > 0, "Empty cross-chain data");
        require(r.dstChain == chain(), "Dst chain not match");
        require(
            r.op == Operation.CrosschainConfirm,
            "Not CrosschainConfirm request"
        );
        require(r.confirmed == true, "Not confirmed");

        bytes32 srcHash = abi.decode(r.extra, (bytes32));

        // Set to request to calc hash.
        require(
            r.getCrossSourceRequestHash() == srcHash,
            "Source request hash is incorrect"
        );
        require(
            crosschainRequestConfirmation[srcHash] == bytes32(0),
            "Source request already confirmed"
        );

        // Save request.
        r.nonce = nonce(); // Override src nonce to dst nonce.
        _dsthash = _addRequest(r);
        crosschainRequestConfirmation[srcHash] = _dsthash;

        _dstRequest = r;
        emit RequestConfirmed(_dsthash); // auto confirmed.

        // Mint tokens.
        FToken(fbtc).mint(abi.decode(r.dstAddress, (address)), r.amount);
    }

    /// View functions.

    /// @notice The unique chain identifier in FBTC system.
    function chain() public view returns (bytes32) {
        return ChainCode.getSelfChainCode();
    }

    /// @notice The next request id
    function nonce() public view returns (uint128) {
        return uint128(requestHashes.length);
    }

    /// @notice Check whether the address is qualified
    function isQualifiedUser(address _user) public view returns (bool) {
        return qualifiedUsers.contains(_user);
    }

    /// @notice Get all qualified users
    function getQualifiedUsers() external view returns (address[] memory) {
        return qualifiedUsers.values();
    }

    /// @notice Get request by the index a.k.a the id.
    /// @param _id The index.
    /// @return r The returned request.
    function getRequestById(
        uint256 _id
    ) external view returns (Request memory r) {
        require(_id < requestHashes.length, "Request not exists");
        r = requests[requestHashes[_id]];
    }

    /// @notice Get multiple requests by an id range.
    /// @param _start The start index.
    /// @param _end The end index (exclusive).
    /// @return rs The returned requests.
    function getRequestsByIdRange(
        uint256 _start,
        uint256 _end
    ) external view returns (Request[] memory rs) {
        uint256 end = requestHashes.length;
        if (_end > end) _end = end;
        require(_start < _end, "start > end");
        uint256 len = _end - _start;
        rs = new Request[](len);
        for (uint i = 0; i < len; i++) {
            rs[i] = requests[requestHashes[i + _start]];
        }
    }

    /// @notice Get request by hash
    /// @param _hash The hash
    /// @return r The returned request.
    function getRequestByHash(
        bytes32 _hash
    ) public view returns (Request memory r) {
        r = requests[_hash];
        require(r.nonce > 0, "Request not exists");
    }

    /// @notice Get multiple requests by hashes.
    /// @param _hashes The hash list
    /// @return rs The returned requests.
    function getRequestsByHashes(
        bytes32[] calldata _hashes
    ) external view returns (Request[] memory rs) {
        for (uint i = 0; i < _hashes.length; i++) {
            rs[i] = getRequestByHash(_hashes[i]);
        }
    }

    /// @notice Calculate hash of the request.
    /// @param _r The Request to hash
    /// @return _hash The hash result
    function calculateRequestHash(
        Request memory _r
    ) external pure returns (bytes32 _hash) {
        _hash = _r.getRequestHash();
    }
}
